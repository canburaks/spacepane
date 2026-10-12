# Changelogs

Record material changes under dated entries, newest first. Distinguish research, implementation, and validation. Dates use Europe/Istanbul.

## 2026-10-12 — The website and the static reference left this repository

- Implementation: the folder was split into a workspace of three repositories as planned in [docs/plans/2026-10-12-three-repository-split-plan.md](docs/plans/2026-10-12-three-repository-split-plan.md). This tree is now `spacepane/`; `web/` and `Website/` moved to the private sibling `spacepane-web/`, and the public CAD source mirror is `spacepane-cad-source/`. This entry covers Phase 2, the app repository, and is authored on disk before the repository's first commit (no `.git` existed in the tree while it was edited).
  - `script/check_static.py` loses `website_step` and the "website data" step, whose three `node web/...` commands have no target here; `script/test_check_static.py` drops the step name and the `website` workstream from its expectations (the slug-alias test now uses `lead`, the workstream-name set and the additions-file loop no longer list `website`).
  - `tools/ownership.json` loses the `website` workstream; `tools/check_ownership.py` had no mention of it.
  - The app icon source is now `Configuration/AppIcon.svg` (a byte-identical copy of the website's `public/images/icon.svg`): `script/generate_app_icon.swift` (comment and path) and `README.md` read it. `Configuration` is a plain Xcode group listing only xcconfig, plist, entitlement and `.xcstrings` files, not a file-system-synchronized group, and no build phase references an SVG, so the file is not bundled into the app.
  - Store tooling now in this tree: `script/store-preview/design/render.mjs` takes Playwright from the `spacepane-web` checkout named by `SPACEPANE_WEB_REPO` (default `../spacepane-web` beside this repository) and exits with a clear message when it is absent; `script/store-preview/remotion/scripts/make-assets.mjs` copies `Configuration/AppIcon.svg`; comments and README lines in `script/store-preview/**`, `script/store-screenshots/compose.sh` and `script/compose_store_screenshot.swift` that cited `web/...` now name the `spacepane-web` repository (`footage/icon.svg` in the design project is byte-identical to `Configuration/AppIcon.svg`).
  - `AGENTS.md`: the website bullet now says the site lives in the private `spacepane-web` repository, that nothing here may depend on it or copy from it (ShadCN Blocks licence), names the four paths its sync script reads as a contract, and notes that the support and privacy URLs and the open-source offer link in `Configuration/Branding.xcconfig` must keep resolving.
  - `PLAN.md`: the open website items point at the `spacepane-web` repository; the icon-source instruction is replaced by the fact that it moved on 2026-10-12. No box was ticked.
  - `.gitignore`: ignores `docs/release/store-listing/app-preview/**/*.mp4` (owner decision: the two candidate videos stay out of git) and drops the `.netlify` rule. `script/store-preview/remotion/node_modules/` is ignored by `script/store-preview/remotion/.gitignore` (`node_modules/`); the design project's own `.gitignore` does the same.
  - Wording only, in `docs/release/publishing-roadmap.md` and `docs/release/store-listing/app-store-connect-worksheet.md`: the website items say they live in the `spacepane-web` repository. Historical records under `docs/decisions/`, `docs/validation/`, `docs/reviews/`, `docs/initial/`, `docs/plans/` and earlier entries here are unchanged.
  - No Swift source, Xcode project, CAD-mirror file or `Local.xcconfig` was edited. No LICENSE file was added (the licence is an open owner decision).
- Validation (Mac, Xcode 27.0; cleared only `.build/xcode`, `.build/validation` and `Packages/PreviewCore/.build` first, since they embed the old absolute path):
  - `python3 script/test_check_static.py`: 112 tests, OK (5 skipped: the tree-sitter parser tests, because the package is not installed).
  - `./script/build_and_run.sh --check-static`: 21 passed, 1 skipped (swift syntax, tree-sitter not importable), 0 failed.
  - `python3 script/package_cad_source_offer.py --check`: ok, 34 files, OCCT 7.9.3.
  - `xcrun swift script/generate_app_icon.swift --check`: "App icon verified: 10 images in AppIcon.appiconset." (`--check` does not read the SVG; it was not re-rendered.)
  - `./script/build_and_run.sh --check`: exit 0; manifests, 4 Xcode targets, 76 catalog formats, 1100 localization keys in 14 locales.
  - `./script/build_and_run.sh --test`: exit 0; Swift Testing runs of 3708 tests in 417 suites (2 known issues, `LogicalLineNumberTests.swift:150` and `Q72TableTabStopsTests.swift:250`, both recorded as known by the tests themselves) and 74 tests in 11 suites passed, plus the isolated model checks and the adversarial corpus (648 cases, 81 formats).
  - After `git init`: `python3 tools/check_ownership.py --audit` exits 0 with 0 unowned files among 1,298; the one new glob without a match is `.claude/**`, because `launch.json` moved to the website repository. `./script/build_and_run.sh --check-static` passes again (21 passed, 1 skipped).
  - Not done: the icons were not re-rendered from the new source, and no store-preview film was rendered through the changed Playwright lookup.
- Also on 2026-10-12, outside this tree: the pre-split history (11 commits) is archived only in a local backup and was not carried over, so this repository starts from one commit; `script/store-preview/remotion/public/audio/score.wav` is ignored because `scripts/make-audio.mjs` regenerates it on every render; the mirror `spacepane-cad-source` was refreshed locally to this tree's bundle (the mirrored files are unchanged since commit `e3ab9f3`, the tree build 1.0.0 (1) was made from) and tagged `1.0.0-build.1`, not pushed.
  - `render.mjs` was syntax-checked and its missing-checkout message was exercised with `SPACEPANE_WEB_REPO=/nonexistent`; no film was rendered.

## 2026-10-12 — Plan for the three-repository workspace

- Research: four read-only agents audited the cross-repository couplings and the git history, surveyed multi-repository tools, and read the Turborepo/Nx documentation, the ShadCN Blocks licence and the OCCT layout question. Findings: Turborepo and Nx work inside one repository and do not fit; `mani` is the workspace tool; the history holds no credentials or private CAD models, but every commit touching `web/` also touches app files, so the app and the website start from fresh history.
- Plan: [docs/plans/2026-10-12-three-repository-split-plan.md](docs/plans/2026-10-12-three-repository-split-plan.md) turns this folder into a workspace holding `spacepane/` (the app), `spacepane-web/` (private, the Next.js site with `Website/` inside it) and `spacepane-cad-source/` (the public mirror). It lists the file moves, the edits each repository needs with file and line, five open owner decisions, the checks and the rollback.
- State: plan only. No file was moved, no repository created and nothing pushed. The owner deleted `canburaks/spacepane` on GitHub on 2026-10-12, so the local `.git` is the only copy of this repository's history until the split is carried out.

## 2026-10-12 — Two App Store preview video candidates

- Implementation: two candidate app preview videos for the Mac App Store, made by two agents from the same real window captures as the chosen screenshots (`.build/store-screenshots/raw/`, development-signed build, GitHub Dark). Neither is chosen and nothing was uploaded.
  - `script/store-preview/remotion/` (Remotion project, pinned versions) renders `docs/release/store-listing/app-preview/remotion/spacepane-preview.mp4` and `poster.png`: 29.0 s, with a synthesized soundtrack.
  - `script/store-preview/design/` (one hand-written HTML/CSS/JS film stepped frame by frame in headless Chromium with the website's Playwright, encoded with ffmpeg) renders `docs/release/store-listing/app-preview/design/spacepane-preview.mp4` and `poster.png`: 29.8 s, silent audio track.
- Validation: `ffprobe` on both files reports 1920×1080, 30 fps, H.264 High level 4.0, yuv420p, stereo AAC at 48 kHz, about 11 Mbps, about 40 MB each, which matches Apple's Mac app preview specification as the agents read it on 2026-10-12 (https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications). Frames were reviewed as contact sheets; neither video was watched in playback or tried in the App Store Connect uploader.
- Open before either is used:
  - Both are animated still captures, not a screen recording. Guideline 2.3.4 says previews may only use video screen captures of the app; whether App Review accepts staged stills is unverified.
  - The design version's Theme scene dissolves to the Aurora scheme, which build 1.0.0 (1) at App Store Connect does not contain. Remove that beat unless a build with Aurora is the one submitted.
  - The Remotion version's archive scene shows the macOS "Uncompress" title-bar button for about a second beside "Nothing is extracted".
  - The footage is from the development-signed build, so the screenshots' store-build confirmation gate applies to the video too.
  - Remotion's licence is free for individuals and organisations of up to three employees and paid above that; the owner confirms which applies. Nothing from it ships in the app.

## 2026-10-12 — Owner chose the store screenshot set

- Decision: the nine images in `docs/release/store-listing/screenshots/` (vivid gradients, GitHub Dark) are the set for the Mac App Store listing. The alternative in the website's dark style with the Aurora scheme was not chosen; those images show a scheme that build 1.0.0 (1) at App Store Connect does not contain. `docs/release/store-listing/screenshots.md` records the choice. Nothing was uploaded; confirming the Finder scenes on a store-signed build is still open.

## 2026-10-11 — Aurora: the website's preview palette as a twelfth color scheme

- Owner decision: the palette of the website's live preview becomes a real scheme in the app, so store screenshots and the website show colors the app can draw. `PreviewColorSchemeID` gains `aurora` (dark, last in the dark picker); `NativeColorSchemes.aurora` holds the website's values (`.qv` in `web/src/styles/preview-theme.css`: background `0x1B1C21`, pink keywords, cyan types, violet literals). One value differs: the website's comment ink measures 3.47:1 there, so the scheme uses `0x7F8393`, the smallest step toward white that reaches 4.5:1. The settings schema stays 6. Decision 023 carries the amendment; the notices table lists Aurora as original to the product.
- Name "Aurora" in 14 languages through `tools/localization/additions/release-aurora-scheme.json` (drafts, like the rest). Website: the scheme is in `color-schemes.json`, `capabilities.json`, the `ColorSchemeId` enum, a `[data-scheme="aurora"]` block, the 14 locale name lists and the support answer that lists the schemes. The website's unnamed default still draws this palette under the name Standard, which the app's Standard dark palette does not match; that is left as it was.
- Tests: scheme counts and lists updated (12 schemes, 13 normal palettes); a new test pins the website's values with independent literals and the one raised ink. The color scheme, schema and gallery suites pass, `./script/build_and_run.sh --check` and `--check-compiler` pass, and `npm run check` passes in `web/`. The Release app builds; the Theme page shows the Aurora tile and a notebook preview in Finder draws pink keywords on the new background.
- The full suite has one failure that is not from this change: `figuresAndCoversAreNamedLikeTheirAccessibilityLabels` reports "Figure 1 of 3" where it expects "Figure 2 of 3". It fails the same way on an untouched copy of the last commit and passed on 2026-10-10, before the Mac's built-in display was switched from 2624 x 1640 at 1x to 2056 x 1329 at 2x. Not fixed here.
- Found while selecting the scheme by automation: the scheme tiles expose no accessibility name or selected state, and an accessibility press on a tile did not change the scheme in several attempts, while a mouse click did. A VoiceOver user may not be able to choose a scheme. Not fixed here.
- Screenshot candidates in the website's look (its dark stage, an aurora eyebrow bar and one gradient headline line) were composed from nine Retina captures of this build with Aurora selected: `.build/store-screenshots/website-theater/` (not tracked). They show a scheme that build 1.0.0 (1) at App Store Connect does not contain, so they fit a later build only, and the listing's "11 color schemes" becomes 12 with that build.

## 2026-10-11 — App Store screenshot candidates and the tooling that makes them

- Added nine 2880 × 1800 images without alpha in `docs/release/store-listing/screenshots/`: real captures of Finder's Quick Look panel and of the companion on vivid gradients from the website palette, with the headlines of `docs/release/app-store-listing.md`. Owner decisions that day: headline above a real capture, nine scenes, vivid gradients, GitHub Dark, capture from the local build now and confirm on the TestFlight install before submission. `docs/release/store-listing/screenshots.md` records the scenes, the method and what is still open.
- Tooling: `script/generate_store_demo_files.py` (synthetic "Harbor" files, including a generated AP214 gear that the CAD preview renders with 64 faces), `script/store-screenshots/capture.sh` with its AppleScript helpers (stage a clean Finder window, drive Quick Look and the companion through accessibility, capture windows by number, restore Finder), `script/compose_store_screenshot.swift` and `script/store-screenshots/compose.sh` (layout only; captures are never enlarged or retouched).
- Evidence and limits: captured on macOS 27.2 at 2 pixels per point from the development-signed Release build registered from `.build/xcode`; every scene rendered in SpacePane there, including STEP. Nothing was observed on a store-signed build, and nothing was uploaded to App Store Connect. Two images show the system's "Open with" button naming this Mac's default apps for the type.
- Observed in the app while capturing, not fixed: `deploy.yaml` shows "Structured view is unavailable"; wrapped headings in the Contents rail overlap; the Theme page's scheme tiles expose no accessibility label or selected state; pressing the light "Standard" tile did not change the selection.
- Later the same day, on the owner's request to remove other vendors' app names: `generate_store_demo_files.py` binds the notebook and the SQLite demo files to Xcode with a per-file "Open with" attribute, so Quick Look's button no longer names this Mac's default apps for those types; no system default changed. The set was retaken and recomposed. The capture step now selects the scheme with a real mouse click and verifies the zoom by comparing captures (the first check compared two files that were never written and always passed).

## 2026-10-10 — First upload to App Store Connect: 1.0.0 (1)

- Validation, on the owner's instruction: `./script/build_and_run.sh --upload` sent the signed archive built earlier that day (the tree of commit `e3ab9f3`, Xcode 27.0) to App Store Connect with a Team API key. xcodebuild reported "Uploading “SpacePane.pkg” is complete", "Uploaded package is processing", "Upload succeeded" and `** EXPORT SUCCEEDED **`. This is the first time Apple's upload validation accepted this bundle layout: the XPC service nested in the preview extension, extensions without their own embedded profile, the team-prefixed App Group and four privacy manifests.
- One warning, not a failure: "Upload Symbols Failed. The archive did not include a dSYM for the CADWorker". The helper is built by CMake outside Xcode and has no dSYM in the archive, so crashes inside the helper will not be symbolicated by Apple.
- The key file and the issuer ID stay in `~/.appstoreconnect/` on the owner's Mac; neither is in the repository or in any log kept here.
- Not established: App Store Connect's processing result, export-compliance and TestFlight state, any install of the store-signed build, and everything decision 027 D27 asks for. Nothing was submitted for review. The next upload needs build number 2.
- A development-signed Release build was also launched locally the same evening for the owner to try (`PREVIEW_BUILD_CONFIGURATION=Release ./script/build_and_run.sh --verify`); it registers one preview and one thumbnail extension from `.build/xcode` and must be unregistered again before a store build is installed.

## 2026-10-10 — Listing text entered in App Store Connect as a draft; changelog merge repaired

- App Store Connect, not the codebase: the English (U.S.) and English (U.K.) listing from [the listing content](docs/release/app-store-listing.md) was entered for version 1.0 of the app record and saved. That is the name `SpacePane for Quick Look`, the subtitle, promotional text, description (3,721 and 3,724 characters), keywords, and the support, marketing and privacy URLs. Each value was read back from the page after saving, and the three addresses returned HTTP 200. The owner saved the name and subtitle, which settles owner decision 1 in the listing.
- Nothing was uploaded, added for review or submitted. Left as found: categories (Utilities, Developer Tools), SKU, primary language. Still empty: copyright, screenshots, the App Privacy questionnaire, age rating, content rights, the Digital Services Act declaration and the review information. The record's version reads `1.0` and the build's `1.0.0`; that difference is recorded, not resolved.
- Documentation: the listing has a new section, "What App Store Connect holds", and its status line no longer says nothing was entered. The store-listing worksheet and README and the submission worksheet point to that section.
- Changelog repair: the merge in commit `e3ab9f3` left an earlier draft of the entry below under a second copy of the heading "Public source repository for the CAD helper". That block is removed. The real entry of that name, further down, is unchanged and identical to the one committed with the source offer; no entry was lost.
- Verified: `python3 script/check_static.py` (22 passed, 1 skipped for the missing tree-sitter packages). PLAN checkboxes are unchanged.

## 2026-10-10 — App Store listing content and its research brought into this repository

- Documentation only; no source change and nothing entered in App Store Connect. [The listing content](docs/release/app-store-listing.md) and [the listing research](docs/market/2026-10-10-app-store-listing-research.md) were drafted in the working tree of the sibling `prev` checkout and are copied here, because this is the publication repository. The listing holds the English (U.S.) and English (U.K.) name `SpacePane for Quick Look`, subtitle, keyword field, promotional text and description, a ten-image screenshot plan, fallback names, a claim check and draft subtitle and keyword lines for nine other store languages. The research file is unchanged from the `prev` draft.
- One change to the listing against the `prev` draft: the description ends with the Open CASCADE paragraph that the entry "Where the OCCT offer is shown" below asks for while STEP and IGES ship. Recounted by script: name 24 and subtitle 30 characters (limit 30), keywords 98 bytes (limit 100), promotional text 159 characters (limit 170), description 3,721 characters for U.S. English and 3,724 for U.K. English (limit 4,000).
- Not in this commit: the earlier listing draft under `docs/release/store-listing/` and the rewritten submission worksheet are uncommitted work of another session. Notes that mark the earlier draft as superseded and point its worksheet at the new name and subtitle were written into those files and travel with them.
- Not changed: the metadata rule in [app-store-submission.md](docs/release/app-store-submission.md) against Apple product names in the app name stands until the owner decides (decision 1 in the listing), `PREV_APP_CATEGORY` stays Utilities (decision 5), and PLAN checkboxes. The owner decisions and the claim check in the listing remain open.

## 2026-10-10 — Where the OCCT offer is shown: About, the website and the store text

- About: the Acknowledgements card now shows OPEN CASCADE SAS's copyright line and a link row, "Open-source notices", to the public repository `canburaks/spacepane-cad-source`. The address is configuration like the other About links: `PREV_OPEN_SOURCE_URL` in `Branding.xcconfig`, `PreviewOpenSourceURL` in `App-Info.plist` and `HostedConfiguration.Links.openSource` (https only, hidden when unset). The Resources section now appears only when it has rows, because the open-source link sits with the acknowledgements.
- Two new strings, `about.acknowledgements.openCascade` and `about.link.openSource`, in all 14 languages through `tools/localization/additions/release-open-source-offer.json`. The 13 translations are drafts for native review, as before. The Hausa glottal stop uses U+02BC and French values need no extra spacing rules.
- Website (`web/`): a `/open-source` page in all 14 languages (namespace `openSource`, `src/features/docs/open-source`), a footer link on the home and document pages, two rich-text tags (`sourceLink`, `releaseLink`) and `src/data/open-source.json` for the repository URL, the releases URL and the OCCT version. The contact is the existing `<email/>` tag. The static `Website/` reference has no such page and is not changed.
- Store: the worksheet in `docs/release/app-store-submission.md` has a row with the paste-ready description line. That file is being rewritten by another session, so the row is in the working tree and not in this commit.
- Verified:
  - `python3 tools/validate_localization.py` and `python3 tools/test_localization.py` (103 tests) pass.
  - The package builds and the four host sources (`Apps/PrevApp`, both extensions, `CADImportService`) type-check with Swift 6.4 in a fresh scratch build. The repository's own `Packages/PreviewCore/.build` came from `prev` and its module cache names the old path, so `--check-compiler` fails there; that is build state, not source.
  - 18 focused Swift tests pass, including the new `theOpenSourceLinkNeedsHTTPSAndCountsAsAConfiguredLink` and the localization resource suites.
  - In `web/`, `pnpm run check` passes (0 errors; the 2 existing warnings are in vendored files) and `pnpm run build` generates `/open-source` for all 14 locales (84 static pages). The built English and Turkish pages have the four headings, both GitHub links and the `info@spacepane.com` mail link.
- Not verified: the About row in a running signed app, translated layout and VoiceOver, the deployed website, and the legal review of the offer. PLAN.md is not updated here because another session is editing it; the OCCT obligation stays open until counsel has reviewed the offer.

## 2026-10-10 — Signed archive and App Store Connect export from this repository; two archive-script defects fixed

- First full build in this checkout after the move from `prev`, on the Mac (Xcode 27.0, Swift 6.4), with every change of the day in the tree: `./script/build_and_run.sh --check` passes; `--check-compiler` typechecks the app, both extensions and the CAD service; `--test` passes (3,707 tests in 417 suites with 2 known issues, the 74 serial tests, the companion model, gallery, SQLite and appearance checks and the 648-case adversarial corpus); `--archive` succeeds and `check_release_archive.py` passes for 1.0.0 (1) with 6 Mach-O files, 4 sandboxed bundles, 2 helpers and 4 privacy manifests; `--export` succeeds and reads back Apple Distribution signatures on the app, both extensions and the CAD service, with the sandbox and `inherit` on both helpers. Nothing was uploaded.
- Two build caches copied from `prev` named the old checkout and broke the first runs: `.build/cad` (CMake caches and file lists) and `Packages/PreviewCore/.build` (precompiled module caches). Both were removed and rebuilt here; the CAD helper's 13 process checks pass.
- `script/build_and_run.sh`, archive step: Xcode moves the intermediate app into the archive, so the earlier loop over what is on disk found nothing and left a LaunchServices record and two PlugInKit records naming a deleted path, which is how the dangling registrations on this Mac arose. The step now removes every PlugInKit record under `.build/xcode-archive/` by its recorded path and unregisters the intermediate app by name. After `--archive` and `--export`, `pluginkit -mAD` and the LaunchServices dump show no SpacePane entry.
- `script/build_and_run.sh`, export step: `ls` on a missing `.app` failed under `pipefail` and ended the script with status 1 before the package branch, although the export itself had succeeded. The two lookups now tolerate no match, and the package read-back runs.
- `script/check_release_archive.py` requires `Contents/Resources/ColorSchemes-Notices/NOTICE.md` in the app (with its test); `tools/ownership.json` lists the two new companion files.

## 2026-10-10 — About opens the bundled license notices; the color scheme notice ships

- About: the Acknowledgements card has two button rows, "Open CASCADE license texts" and "Color scheme notices". Each opens, in Finder, the folder of notices stored inside the app, through `NSWorkspace.shared.open`. A run that lacks a folder shows no row; if the system cannot open a folder the row says so and VoiceOver announces it. New `BundledNotices` (model) and `AboutNoticeRow` (view) in `Apps/PrevApp`; the folder is a synchronized group, so the project file is unchanged.
- Four strings in 14 languages through `tools/localization/additions/release-bundled-notices.json`; the 13 translations are drafts. `validate_localization.py` and `test_localization.py` pass.
- `ThirdPartyNotices/ColorSchemes/NOTICE.md` is now bundled as `Contents/Resources/ColorSchemes-Notices/NOTICE.md` in the app and in the CAD service, by `script/embed_cad_worker.py` and `script/stage_companion.py`. `script/build_cad_worker.py` owns `NOTICE_FOLDERS` and declares every input and output in the generated file lists; a missing folder lists nothing, so the published CAD source bundle still relinks. Six new tests in `script/test_build_cad_worker.py` failed against the old scripts and now pass.
- Verified on the Mac the same day: the app target compiles and archives with these sources, and the signed archive and the exported app contain both notice folders. Not observed: the rows in a running app, Finder opening a folder from the sandboxed app, translated layout and VoiceOver; the row in `docs/validation/pending-mac-verification.md` lists them.
- Open: `ThirdPartyNotices/OCCT/NOTICE.txt` still carries development-build wording, and the mirror repository `spacepane-cad-source` was generated before `build_cad_worker.py` and `embed_cad_worker.py` changed, so it needs regenerating before its next release.

## 2026-10-10 — CAD peer requirement accepts the TestFlight signature

- `CADPeerRequirement` now emits `anchor apple generic and identifier "<id>" and (certificate leaf[field.1.2.840.113635.100.6.1.9] exists or certificate leaf[field.1.2.840.113635.100.6.1.25.1] exists or certificate leaf[subject.OU] = "<team>")`: the Mac App Store marker, the TestFlight marker or the team organizational unit, still anchored to Apple and to the exact identifier, with the same allow-list on both interpolated values. The doc comment no longer says TestFlight carries the Mac App Store marker; it states that only the organizational-unit form can name the team and that the TestFlight leaf's organizational unit reads `TESTFLIGHT`. The comment in `Native/CADImportService/main.swift` and the note printed by `script/check_release_archive.py` (with its test) name the three forms.
- Tests first, on a Mac: three expectations (the full literal text, the exact list of three alternatives, Security's readback containing `6.1.25.1`) failed against the old code for the right reason, then passed; two property tests were added. `swift test --filter PreviewCADFormatsTests`: 92 tests in 9 suites passed. `python3 -I script/test_check_release_archive.py`: 73 tests passed.
- Verified read-only with `codesign --verify -R` on other vendors' installed apps, not on a SpacePane build: the generated text passes against a TestFlight-delivered app (the old two-branch shape fails there), four Mac App Store-delivered apps and a Developer ID app with the right team; a wrong team, a wrong identifier and the TestFlight marker alone against a Mac App Store app fail.
- Still open (decision 027, D27): an installed TestFlight build of SpacePane proves the TestFlight form and a store-delivered build proves the Mac App Store form. The open row in `docs/validation/pending-mac-verification.md` says what to record.

## 2026-10-10 — Remove earlier development builds from the Mac; publication preparation starts

- On the owner's instruction, removed the traces of earlier builds from the development Mac so that an installed store build is the only provider with this identity: stopped the one running thumbnail extension process, removed four PlugInKit registrations (two pointed at a deleted archive path) and eleven LaunchServices app records, and deleted the Xcode build, archive and export folders in this checkout, in the `prev` checkout and in two of its worktrees, both `dist/PrevPrototype.app` copies, two empty `DerivedData/Prev-*` folders, the Application Scripts folders, the Metal shader caches, the prototype preferences folder and the three prototype provisioning profiles. Afterwards `pluginkit -mAD`, the LaunchServices dump and Spotlight show nothing for the three identifier generations.
- Not removed: the eleven sandbox containers and three group containers, which hold the saved settings. macOS privacy protection refused the terminal (`Operation not permitted`); they are the owner's to delete in Finder or after granting Full Disk Access. Also left: the `DerivedData` index folder of the project open in Xcode, the Trash copy of the prototype app, a synthetic fixture folder in iCloud Drive, and the `prev` clone itself. The Quick Look thumbnail cache, Finder and the extension's enabled state were not touched.
- `script/build_and_run.sh`: the archive step now removes the intermediate app's extensions from PlugInKit as well as the app from LaunchServices. The missing step is what left the dangling registrations.
- The copied `.build/cad` named the old checkout in its CMake caches and file lists; removed `kernel-arm64`, `worker-arm64` and the two file lists and rebuilt the helper here.
- The App Store Connect key file was moved from `~/Downloads` to `~/.appstoreconnect/private_keys/` (directory mode 700, file mode 600). Nothing about it is in the repository.
- A verified git bundle of every `prev` branch and its stash is at `~/prev-all.bundle`.
- `AGENTS.md` and `PLAN.md` now say publication preparation is the active work and that uploading, submitting and releasing happen only on the owner's explicit instruction. `PLAN.md` M6 points at the publication plan and records the contact address decision.

## 2026-10-10 — Consolidate the App Store publishing documents from prev (documentation only)

- Copied the untracked `docs/release/app-store-publishing-guide.md` and `docs/initial/08-app-store-publishing-research.md` from a `prev` worktree and corrected the facts found outdated: four privacy manifests now exist; Apple sets no minimum Xcode or SDK for macOS uploads; App Group guidance (the team-prefixed form is kept); the 2026 age-rating questionnaire; 50 metadata locales without Kurmanji or Hausa; a Team key with the Admin role is recommended; a TestFlight build is signed with the TestFlight certificate, not the Mac App Store one. Owner statements (app record, API key, price, `info@spacepane.com`) are recorded as statements, not checked.
- Three-way merged the worktree's edits to `docs/release/app-store-submission.md` (base `3339304`; one conflict, in "Archive and validate"). Added the canonical privacy and support URLs, `info@spacepane.com`, the 2026 age-rating answers, and review-note sentences for the `public.data` declaration, the `com.quicklookpro.file.*` aliases, Apple silicon only and the optional OCCT-based STEP and IGES previews with the source repository (no legal review is claimed). The notes are 2,714 bytes with placeholders.
- `docs/release/testflight.md`: `master` became `main`, the key role became Team/Admin with its caveat, and a "Local upload from the Mac" section was added. A dated correction note was appended to `docs/validation/2026-10-10-testflight-dry-run.md`.
- Recovered `docs/release/publishing-roadmap.md` from the `prev` stash as a 2026-10-06 snapshot with its superseded points listed. Restored `.claude/launch.json` and `.codex/environments/environment.toml`, which the copy from `prev` had missed. `README.md` says publication preparation started and nothing has been uploaded.
- Validation: `./script/build_and_run.sh --check-static` passes (22 passed, 1 skipped for the missing tree-sitter packages).

## 2026-10-10 — App Store listing drafts

- Added `docs/release/store-listing/` with English drafts for the 1.0.0 listing: `listing.en.md` (name, three subtitle candidates, promotional text, description, keywords, What's New, claims left out), `screenshots.md` (shot list with provenance and Finder-observation gates), `app-store-connect-worksheet.md` (categories, age rating, App Privacy, export compliance with the encryption-API findings, pricing, owner checklist, the store-locale table for the 14 app languages) and a README.
- Limits measured by command: description 3,876 of 4,000 characters, keywords 98 of 100 bytes, promotional text 162 of 170, recommended subtitle 28 of 30.
- The text claims no Finder routing and no thumbnail for any named type: `host-matrix.json` records a Finder preview for 4 of 76 types and Finder thumbnails for none, all on development-signed builds. The encryption search found hashing, certificate inspection and encrypted-entry detection only, and no decryption; the declaration remains the owner's. Nothing was entered in App Store Connect.

## 2026-10-10 — Contact address is info@spacepane.com on the website

- Owner decision: the contact address is `info@spacepane.com`. `web/src/data/brand.json` `supportEmail` and the static reference `Website/support.html` changed from `support@spacepane.com`; `Website/privacy.html` was regenerated with `npm run static:sync`. No locale file held a literal address, and the app shows none.
- Verified: `npm run check` passes (data, static privacy, locale and script tests, typecheck, lint with two existing warnings). `visual:compare` on the privacy page matches except the 375 px header at 0.55%. The support page differs about 24% from the static reference, identically before and after this change, so that gap already existed.
- The live site keeps the old address until the website is deployed.

## 2026-10-10 — App Store publication plan (research and planning only)

- Research: five parallel read-only reviews covered the traces of earlier builds on the development Mac, the signing and export pipeline, Apple's current Mac App Store requirements (primary sources read 2026-10-10), the open release gates in this repository's records and what the move from the `prev` repository left behind.
- Added `docs/plans/2026-10-10-app-store-publication-plan.md`: the owner decisions, an ordered runbook for removing the development builds and their data from the Mac, the changes needed before a first upload, the upload and TestFlight validation steps, the store listing work, the retirement of `prev` and a file-ownership split for execution.
- Finding, verified with `codesign --verify -R` against a TestFlight-delivered app installed on this Mac: a requirement of the shape `CADPeerRequirement` emits (Mac App Store leaf marker or team organizational unit) rejects a TestFlight signature, whose leaf carries `1.2.840.113635.100.6.1.25.1` instead; adding that marker makes it pass. The comment in `CADPeerRequirement.swift` that TestFlight carries the Mac App Store marker is therefore wrong. No code was changed.
- Owner decisions recorded in the plan the same day: the price is set in App Store Connect (roughly USD 9.99, local pricing adopted); the contact address is `info@spacepane.com`; no macOS 15 machine is available for validation, which leaves the minimum-system question open.
- Nothing was executed: no file outside `docs/plans` and this changelog was edited, nothing on the Mac was deleted or unregistered, no build was made and nothing was uploaded. No plan box changes.

## 2026-10-10 — Public source repository for the CAD helper (OCCT LGPL route, no purchased license)

- Decision: the main repository stays private. The fee-free OCCT route (decision 027 D20 (a)) publishes only the CAD helper's corresponding source, with the written offer, as a sibling repository. The Open CASCADE commercial exceptions (EUR 3,500 and EUR 20,000 in their reply) are not taken.
- `Native/CADWorker/LICENSE` is new: the MIT License, Copyright (c) 2026 Can Burak Sofyalioglu, for the helper's sources, the build and embedding scripts and the entitlements file. LGPL 2.1 section 6 needs terms that permit modification for the recipient's own use and reverse engineering to debug it; the repository had no license at all. The choice of MIT is a default, not a reviewed decision.
- `Native/CADWorker/SOURCE-OFFER.md`: filled the two placeholders (requests to `info@spacepane.com`; download location `https://github.com/canburaks/spacepane-cad-source`, whose release tarballs also carry the pinned archive), added the helper license paragraph and reworded the status. It stays "pending legal review"; no counsel has reviewed it.
- `script/package_cad_source_offer.py`: the bundle now has a root `LICENSE` and a generated `README.md` (what is here, the rebuild and relink steps); `--check` fails on a missing or empty helper license and on any unfilled "to be supplied" or "to be published" placeholder in the offer; a `.git` directory inside a bundle is ignored, so a repository that mirrors a bundle is checked in place with `--check <directory>`. Five new tests (57 in all).
- Created the sibling repository `/Users/cbs/Github/spacepane-cad-source`: one commit, 34 files, generated by `package_cad_source_offer.py --output` and committed as-is. It is local only: nothing was pushed, no GitHub repository was created and no release was made.
- `Native/CADWorker/README.md` and `docs/dependencies/occt.md` describe the mirror and what stays open.
- Verified: `python3 -I script/test_package_cad_source_offer.py` (57 tests), `package_cad_source_offer.py --check` (34 files), `--check` on the sibling repository and `shasum -a 256 -c MANIFEST.sha256` there, `script/check_static.py` (22 passed, 1 skipped) and `./script/build_and_run.sh --check`.
- Relink proof, on a scratch copy of the sibling bundle (its first generation; the later commit changed only documentation) with the pinned archive copied from an earlier build cache: `python3 script/build_cad_worker.py --architecture arm64 --test` built the static kernel and `CADWorker` in 3 min 59 s and passed the 13 worker process checks. Appending a probe string to `src/Standard/Standard_Transient.cxx` in the unpacked tree and running the same command relinked a new helper in 26 s: its SHA-256 changed, the probe string was in the binary and the 13 checks passed again. The archive download path was not exercised, and only arm64 was built.
- Not done: creating the public GitHub repository, tagging and attaching the tarball that includes the pinned archive, counsel review of the five questions in the offer, the offer's location in the About text (14 languages), the website and the store description, and a refresh of the mirror at each release. PLAN boxes stay as they were: the OCCT obligation is not closed until the repository is public and the app points to it.
- Note: the bundle includes `docs/dependencies/occt.md`, which records the size and face counts of the private IGES acceptance model, not the model or its hash. Redact that paragraph first if it should not be public.

## 2026-10-10 — App Store Connect export passes on the Mac; the export mode reads the package back

- After the account holder created the Apple Distribution and Mac Installer Distribution certificates, `--export` succeeded with the signed-in Xcode account generating `Mac Team Store Provisioning Profile: org.webmeister.spacepane`. Recorded in [the dry-run record](docs/validation/2026-10-10-testflight-dry-run.md): every bundle and both `CADWorker` copies are re-signed by `Apple Distribution: … (Z743N6D8DS)`, the workers keep exactly `app-sandbox` and `inherit`, the App Group and `CADAllowedClientTeamIdentifier` survive, and `SpacePane.pkg` is signed by the installer identity. `--upload` still waits for the App Store Connect API key and the app record.
- `script/build_and_run.sh`: `PREV_ALLOW_PROVISIONING_UPDATES=1` passes `-allowProvisioningUpdates` without an API key for a Mac whose Xcode is signed in (the `--upload` guard now checks the key variables, not the argument array). An App Store Connect export produces only a `.pkg`, so `--export` now prints the package signature, expands it into `.build/export-expanded` and runs the identity and entitlement read-back on the app inside instead of stopping; a missing product is an error.

## 2026-10-10 — TestFlight dry run on a Mac: unsigned and signed archives pass, export blocked on distribution identities

- Validation only; no source change. Recorded in [the dry-run record](docs/validation/2026-10-10-testflight-dry-run.md). With Xcode 27.0 / Swift 6.4 on macOS 27.2, `./script/build_and_run.sh --archive-unsigned` archived the Release app with the cached pinned OCCT helper and printed the expected composition (both extensions, `CADImportService.xpc`, two `CADWorker` copies, four privacy manifests, `org.webmeister.spacepane` 1.0.0 minimum 15.0); no Swift optimizer crash, so the `@inline(never)` host-session teardown from hosted run 133 compiles here and none of the other nine `isolated deinit` sites needed it.
- `--archive` with the production identities and `CURRENT_PROJECT_VERSION = 2` in the ignored `Local.xcconfig` passed `check_release_archive.py` (6 Mach-O files, 4 sandboxed bundles, 2 helpers, 4 privacy manifests). `--export` failed in xcodebuild: no "Mac App Distribution" or "Mac Installer Distribution" certificate for team `Z743N6D8DS`, no Mac App Store profile, and no App Store Connect API key to enable `-allowProvisioningUpdates`. `--upload` was not attempted. The pending-verification row for the TestFlight pipeline records the result; the row stays open until the account holder supplies the distribution certificates, the API key and the app record.

## 2026-10-10 — Work around the Release optimizer crash in the host session's isolated deinit (hosted run 133; authored without a compiler, verification pending)

- The second archive dry run reached `xcodebuild archive` and the Swift 6.3.3 compiler (Xcode 26.6) crashed in `EarlyPerfInliner` on `PreviewHostSession.deinit` under `-O -whole-module-optimization`; the Debug package builds and the Mac's Xcode 27 Release builds never hit it. The deinit now calls an `@inline(never)` private method that cancels the gate; the isolated deinit and its behaviour stay. Recorded for the Mac session: a Release build with Xcode 27 should still pass, and the other eight `isolated deinit` sites are not generic classes and did not crash.

## 2026-10-10 — Fix the empty-array expansion in the archive modes (hosted run 131)

- The first archive dry run on the hosted runner built the pinned OCCT helper in eight minutes and then stopped at `ASC_ARGS[@]: unbound variable`: the build script runs under `set -u`, and macOS's bash 3.2 treats an empty array expansion as unbound. The optional argument arrays now expand with the `${array[@]+"${array[@]}"}` form and the emptiness test uses `${array[*]:-}`.

## 2026-10-10 — Archive dry run as an option of the hosted compiler job

- `package.yml` gains a dispatch input `archive`: after the checks (and the tests in full mode) the job writes the PLAN M6 identities to the ignored `Local.xcconfig`, restores the cached OCCT build and runs `--archive-unsigned`. GitHub registers a workflow for manual dispatch only from the default branch, so `testflight.yml` cannot be dispatched until it is merged; this option runs the same dry run from the already registered workflow on any branch.

## 2026-10-10 — TestFlight pipeline (authored without a Mac; the hosted dry run is its first evidence)

- `script/build_and_run.sh` gains `--archive-unsigned` (a Release archive without identities, its composition listed), `--export` (App Store Connect export into `.build/export`, helper identities and sandbox read back after re-signing) and `--upload` (export with the upload destination). All three, and `--archive`, accept an App Store Connect API key through `PREV_ASC_KEY_PATH`, `PREV_ASC_KEY_ID` and `PREV_ASC_ISSUER_ID` (`-allowProvisioningUpdates`). Export options are written per run with the archive's team. `validate_signing.py` prints `team`.
- `.github/workflows/testflight.yml`: a dispatch-only hosted job with three levels (dry-run, signed, upload), the OCCT build cached, the release identities written to the ignored `Local.xcconfig` from repository variables (defaults: the identities PLAN M6 adopted), the build number from the run number, a temporary keychain for the distribution certificates and the API key from secrets, logs and export products kept as artifacts.
- `docs/release/testflight.md`: the runbook (what each level proves, the one-time App Store Connect setup, the secret names, what the TestFlight round must record, what stays open before external testers). PLAN M6 and the submission notes point at it. Signed and upload levels are unverified until the secrets exist; the dry run is dispatched on the hosted runner with this commit.

## 2026-10-10 — Hosted run 123 green; PR #12 marked ready to merge

- Run 123 on `4881570` passed every step (3,704 parallel tests in 417 suites with the 2 known issues, 74 serial tests, integration executables). The PR body now says ready to merge and lists what merging does not claim; the implementation record carries the review round and both runs.

## 2026-10-10 — Fix the locale expectation of the page-position host test

- Hosted run 121 on `44bc298` passed the restyle fix and failed only the third host test, whose premise was wrong: the position wording follows the process language and only the digits follow the presentation locale, so "Page 1 of 10" reads the same in German. The test now uses a 1,200-page comic (the `pageCount` fact) and expects "1.200" after the German display.

## 2026-10-10 — Show a position reported during the restyle, keep the diagram receipt, quiet the fit note (review of batch 4; authored without a compiler, verification pending)

- Two reviewers read the batch 4 production diff (reports under the scratch `agents/reports/`). One defect: `NativeImagePagesView.display` reports its top page while `NativePreviewView.applyStyling` is running, and the header had already been drawn, so a reused column or a new locale showed no "Page n of m" until the next scroll. The restyle now draws the header again when the limits changed during the column's display, and `showPositionLimit` no longer re-enters the restyle; `clearModeViews` resets the position text before the columns report nil.
- `SafePreviewModes` keeps the fence receipt found with the chosen diagram (`diagramReceipt`), so `DrawnModeNotices` no longer re-parses up to 16 fences per display. `NativeDiagramView.reportNotice` compares the whole-percent wording, so a live resize does not re-report the fit note on every pass.
- Not changed, with reasons: a plot step of more than 180 degrees is cut on its short course by design (the wide-frame test expects it); generated front matter alone drops the machine chapter flags, so a user's own keys are shown; language names stay untranslated proper names ("Template", "Assembly" included), per the Q-73 rule; the table width clamp, a per-document measuring budget and the rail's focus-follow question wait for Mac observation and are noted in the queue rows.

## 2026-10-10 — Specify the page position in the preview's limits slot (Q-76)

- `DocumentsQ76PagePositionHostTests` (3) drive `NativePreviewView` with comic-book presentations: the first document shows "Page 1 of 10" after layout, a second document reusing the column shows its own position at once, and a new locale rewords it at once. The review of batch 4 found that a position reported during the restyle is dropped, so the second and third tests fail until the next commit.

## 2026-10-10 — Merge readiness decision for PR #12

- The user asked for PR #12 to be made ready to merge. The immediate workstreams plan's close-out item 3 and a dated note in the continuation plan record the decision and its boundary: merging the development branch is repository integration backed by hosted run 115, and it closes no signed-host or release gate, checks no plan box and removes no "verification pending" sentence. A final review of the batch 4 production diff by two reviewers is in progress; its findings land in their own commits.

## 2026-10-10 — Hosted run 115 green on batch 4

- Hosted macOS run 115 on `8fb7383` passed every step: 3,701 parallel tests in 416 suites with the 2 known issues, 74 serial wall-clock tests in 11 suites, and the integration checks. Recorded in the [implementation record](docs/validation/quality-program-implementation-2026-10-07.md); the four 2026-10-10 queue rows now cite the run; PR #12's body names what the run proves and what still waits for a Mac. The batch 4 changelog entries keep "verification pending" because a hosted compile and package tests are not Finder, signed-host or macOS 15 evidence.

## 2026-10-10 — Serial pass for the live-reload and image-page timing suites (authored without a compiler, verification pending)

- Hosted run 111 (`4f7fbb6`) compiled and cleared the ten deterministic issues of run 109; the two `withKnownIssue` readings record as known. Four waits in untouched suites failed under runner load (`PreviewLiveReloaderTests` twice, `ImagePageSchedulerTests`, `NativeImagePagesViewTests`), different ones from run 109's two. Their five-second `eventually`/`waitUntil` deadlines depend on the shared thread pool, so `script/build_and_run.sh` now runs `LiveReload` (the reloader, monitor and Q153 monitor suites), `ImagePageSchedulerTests` and `NativeImagePagesViewTests` in the serial wall-clock pass; the exact-count guard moves from 6 to 74 tests, counted from the sources and checked by the compiled inventory on the Mac.
- The new tracker test's third expectation had the anchor arithmetic wrong (1 + 99 / 4 = 25 selects the heading at 10); corrected and a second reading added.

## 2026-10-10 — Continuation plan rows for the batch 4 tranches

- `docs/plans/2026-10-07-quality-program-continuation.md`: Q-74 and Q-77 move from researched to partial; Q-72, Q-73, Q-76 and Q-153 name the batch 4 commits, hosted run 109 as the compile evidence, and what stays in the pending-verification queue. No checkbox is marked complete.

## 2026-10-10 — Fix the batch 4 test failures from hosted run 109 (authored without a compiler, verification pending)

- Hosted run 109 compiled the four document tranches and ran 3,768 tests with 12 issues. `ContentsSectionTracker` gains a start-of-text rule: at the top of the text the first heading is current as soon as any heading precedes the anchor, so a dense document no longer opens with its second heading selected; the unit tests and the reference implementation follow it and a new test covers it.
- Test expectations corrected: the diagram floor tolerates a pixel-aligned scale (1e-3); the Persian receipt test asserts the locale digits and no leaked directive, as `PluralStringsTests` does; `Q52NotebookFactsTests` compares against the grouped `renderResult(for:)` layout the preview shows; the table layout width uses a float tolerance; the Contents rail fixture sets the host's layout direction before the constraints are installed.
- Two expectations a Mac must observe are wrapped in `withKnownIssue` and queued: the RTL table column alignment under natural tab stops (Q-72) and the text container tracking the text view in a zero-sized host since the rail joined the text content's leading edge (Q-74). The two timing suites (`ImagePageSchedulerTests`, `PreviewLiveReloaderTests`) were untouched and are watched on the next run.
- Pending-verification queue rows added for the Q-74, Q-77, Q-76 and Q-72/Q-73 tranches with the observations each needs.

## 2026-10-10 — Alert bars, inline chips, table tab stops, heading scale, rules and the code language label (Q-72, Q-73; authored without a compiler, verification pending)

- Q-72: alert bars from palette roles for the five alert kinds, trailing in RTL; inline-code chips whose tint is dropped when it would lower code contrast; table tab stops from measured column widths (numbers right- or decimal-aligned, delimiter colons honoured, wide tables fall back to the plain layout); a modular heading scale relative to the configured size; rules drawn as block edges. All appearance-only, copy byte-exact, VoiceOver text unchanged. Q-73: the card names its language ("Copy <language> code" accessibility label from a fixed table of untranslated language names; a passive text-view layer draws the band); token and unit budgets are named constants with per-language and cap tests; the margin tests pin the scroller style so they no longer depend on order. One string in 14 languages. First uses: `NSTextTab` with `columnTerminators`, `paragraphSpacingBefore`, `layoutManagers`/`firstTextView`. Unverified TextKit assumptions (y-edge orientation, decimal stops, label drawing) and tab stops not re-measured on resize are listed in the queue row.

## 2026-10-10 — Specify block styling and the code language label (Q-72, Q-73)

- Nine `Q72*`/`Q73*` test files and one edited margin test (its button's accessibility label now names the language). These reference the new types, so this RED compiles only with the next commit: a recorded deviation from the plan's compile-first rule, forced by authoring without a compiler.

## 2026-10-10 — Chapter counts, failed page frames, page position and notebook figure lines (Q-76; authored without a compiler, verification pending)

- The EPUB adapter writes `chaptersShown` and `chaptersTotal` beside `partial`, and the rendered notice says "Showing 12 of 38 chapters" (plural, locale digits) from those facts, never inferred in the view. A page that fails to decode draws a framed placeholder with a symbol and a localized label in palette ink (`PageFailureLayout`). The page column reports its top page (`positionNotice`, `onPositionChange`) and `NativePreviewView` shows "Page 3 of 1,200" in the limits slot while Pages is the mode, announcing nothing on scroll. Notebooks rendered through `SafePreviewModes` now use `renderResult(for:locale:)`: thematic breaks separate cell groups and "Figure n, shown in Pages" appears only when placeholders equal valid figures (`NotebookRenderOptions`; the old layout stays the default elsewhere). Two strings in 14 languages. Enclosing cell cards wait for a recorded cell range from the Markup builder.

## 2026-10-10 — Specify chapter facts, the chapter notice and failed page frames (Q-76)

- `DocumentsQ76ChapterFactsTests`, `DocumentsQ76ChapterNoticeTests` and `DocumentsQ76PageFrameTests` compile against the previous tree and fail semantically until the adapter facts, the notice and the frame land. RED cannot be observed here (no compiler).

## 2026-10-10 — Diagram legibility floor, selection receipt, plot notice and antimeridian framing (Q-77; authored without a compiler, verification pending)

- `DiagramFit` keeps the smallest diagram text at 7 pt or more and never magnifies; below the floor the canvas draws at the floor from the top-left corner with a quiet note under it. `MarkdownDiagramFences` gains a typed `Receipt`/`Selection` (total emitted fences, the first 16 tried) and a parse-only `receipt(for:in:)`; `DrawnModeNotices` is the one entry into the limits strip for "Diagram 1 of 3 is drawn" and the plot's long-path notice, hooked from `ModePresentationNotices`. `PlotFraming` frames the short arc across ±180° (−179/179, 0/360, the poles) and cuts lines at the frame edges on their true course. Two strings in 14 languages; the plot caption test now expects the extent alone.

## 2026-10-10 — Specify the diagram floor, receipt notices and plot limits (Q-77)

- `Q77DiagramLegibilityFloorTests` (7), `Q77DiagramReceiptNoticeTests` (8) and `Q77DocumentsPlotLimitsTests` compile against the previous tree and fail semantically until the floor, the hook and the strings land; the pixel test checks that a −179/179 path leaves the middle of a world frame free of ink. RED cannot be observed here (no compiler).

## 2026-10-10 — Add the wide-pane Contents rail (Q-74; authored without a compiler, verification pending)

- `Markup/MarkupContentsRail.swift` wraps the unchanged Contents list in a collapsible leading rail for wide panes; `ContentsRailPolicy` holds the provisional 760 pt threshold (marked for replacement by measured pane widths) with 24 pt hysteresis; `ContentsSectionTracker` maps the visible text range to the nearest preceding heading and pins a chosen heading without stealing focus, announcing or navigating. Arrows act only while the list has focus; Space and Escape stay with Quick Look; copy goes through the injectable pasteboard seam. The hook in `NativePreviewView.swift` and `PreviewTextContentView.swift` places the rail; Contents stays a mode in compact panes. Three strings in 14 languages. The gate's chrome-ink step now returns its constants (a lowercase result crashed the summary).

## 2026-10-10 — Specify the Contents rail, its policy and section tracking (Q-74)

- Four `Q74*` test files (52 tests): rail collapse and width policy with hysteresis, section tracking from visible ranges and pins, focus and key policy, pasteboard injection, and nine host tests that need the preview hook. RED cannot be observed here (no compiler); the Mac runs them first against the previous tree.

## 2026-10-10 — Guard file-opening APIs behind the checked dataless owners

- `script/check_static.py` gains the `dataless guard` step (between `chrome inks` and `swift syntax`): the plan's open-path APIs plus a dozen equivalents may appear only in a pinned allowlist of guarded owners, bundled-resource readers and non-source helpers, each with a one-line reason; a stale entry or an unlisted hit fails, and two pending sites are counted and printed. 112 static-gate tests pass (21 new). Audit result over `Packages/PreviewCore/Sources`, `Extensions` and `Apps`: 35 lines in 18 files, all guarded, resource, non-file or `/dev/null` except the Theme import reader (`BoundedPreferencesData`) and the installed-app scanner (`QuickLookProviderScanner`), recorded as requests R1 and R2 in the implementation record. Python only; no Swift changed.

## 2026-10-10 — Specify the dataless guard step of the static gate

- `script/test_check_static.py` specifies the `dataless guard` step: a flagged file with its line and API, one sample per API id, benign look-alikes, comments and strings, skipped folders, missing root, non-UTF-8 input, allowlisted and undeclared entries, stale entries, the pending count and the step's place in the documented order. RED against the previous gate: 1 failure and 39 errors (authored in the cloud; ran here with `python3 -I`).

## 2026-10-09 — Record the bundle descendant owner check

- The quality-program implementation record now includes the descendant-owner result at `882de4b`: probed opens, unread offloaded children, and `EDEADLK` mapped to unavailable content. `SecStaticCode` still receives the bundle URL. No runtime behavior changed.

## 2026-10-09 — Open bundle descendants through the checked owner

- Bundle file reads and the size walk now stat, open and close through the directory probe. An offloaded child is left unread, and `EDEADLK` on a child becomes unavailable content. Debug `Q153` passed 60 tests in 12 suites; application-bundle tests passed 18; release `Q153Bundle` passed 11. Logs: `.build/quality-work/a1-bundle-green.log`, `a1-bundle-adapter.log`, `a1-bundle-release.log`. `SecStaticCode` still opens the bundle URL inside that same scope.

## 2026-10-09 — Specify bundle descendants inside the checked owner

- Q-153 bundle-owner tests now require Info.plist, the icon, the executable and a nested framework to be opened through the directory probe, an offloaded descendant to stay unread, and `EDEADLK` on a child directory to be unavailable. `Q153BundleOwnerTests` fails those four cases and passes the seven already covered. Log: `.build/quality-work/a1-bundle-red.log`. Production still opens those descendants directly.

## 2026-10-09 — Grant the immediate Q-153, document and image batch

- Record batch base `ebaabbf` and narrow `tools/ownership.json` so q-safety, ux-documents and q-performance can edit their immediate files without sharing the image decoder or the page view. Ownership audit reports no unowned files. No runtime behavior changed.

## 2026-10-09 — Rewrap wrapped text when a legacy scroller narrows the clip

- Measure a wrapped document a second time when showing its vertical scroller shrinks the clip. Overlay scrollers and a scroller reserved before the first layout do not add a pass. Posted mouse events make AppKit select legacy scrollers for the rest of the process, which is what made the narrow code-card test fail only in a full parallel run.
- The narrow LTR/RTL regression passes under an explicit legacy scroller. Two full parallel PreviewCore runs each pass 3,534 tests in 392 suites. Native initial-layout single-pass checks still pass.

## 2026-10-09 — Specify legacy-scroller code cards inside the narrow clip

- Force the narrow LTR/RTL code-card regression onto legacy scrollers, the style AppKit selects for this process after a posted mouse event when scroll bars are automatic. RED compiles and fails the existing width assertion: the text view stays 360 points wide while the clip is 343. Viewport, selection and copy assertions are unchanged.

## 2026-10-09 — Plan the remaining immediate workstreams

- Add [the immediate-workstreams plan](docs/plans/2026-10-09-immediate-workstreams-plan.md): verified starting state at `0465ae9` (17 commits ahead of PR #12), team grants, lead tasks (push, order-dependent margin-test diagnosis), and task-level steps, files, tests and exits for Q-153 bundle descendants/open-path audit/provider cases, Q-72–Q-77 blocks/Contents rail/page honesty/diagrams, and the Q-154 measurement repair, candidate order and escalation. Documentation only; no code or validation changed.

## 2026-10-09 — Apply native code-body highlighting and cap image-report leases at one

- Wire the bounded code-body tokens into the rendered text view: retained across appearance-only restyles, rebuilt on exact content or code-block changes, cleared with the content, and applied after the card styling. The four Q73 highlighting tests pass. The release-image report validator now caps simultaneous native leases at one, matching the new default admission; all six validator tests pass.
- Full PreviewCore run: 1,501 of 1,502 pass. `narrowLongLTRAndRTLContainingBodiesKeepCardPaintAndSelectionInsideTheViewport` fails only in the full run (passes alone and fails identically without this change), so it is an order-dependent layout issue still to diagnose. Static checks: 22 pass.

## 2026-10-09 — Keep bundle parsing inside a checked materialization scope

- Own the whole synchronous bundle parse inside the no-materialization policy, preflight and validate the opened root, and recheck before returning. Complete owners close before restoration; preserve missing/link/file mappings and the existing signature feature.
- Bundle-owner, existing application-bundle and binary-header tests pass in Debug. Descendant requested-file/walk instrumentation and optimized lifetime verification remain the next stages.

## 2026-10-09 — Specify native code-body highlighting

- Add four native regressions for role ink and code fonts, retained card/foreign paragraphs, exact Unicode and language-metadata invalidation, appearance-only reuse and safe mode replacement. RED compiles and reproduces seven missing styling/cache issues.

## 2026-10-09 — Specify complete bundle read ownership

- Add seven owner/scope tests with nine cases covering unavailable roots, policy entry/restoration failures, cancellation and complete-owner lifetime. RED compiles and reproduces 18 missing scope/refusal issues; root-only accounting does not yet prove descendant file/DIR ownership.

## 2026-10-09 — Preserve explicit Mermaid fence identity

- Record exact emitted Mermaid fence boundaries, including empty fences, under the existing metadata budget. Adjacent blocks no longer merge, and empty/unsupported fences consume the bounded search prefix. All six new identity tests pass, including notebook composition and malformed ranges.

## 2026-10-09 — Bound syntax highlighting to explicit safe code bodies

- Tokenize canonical language profiles inside explicit safe bodies with shared UTF-16/token allowances, scalar-safe boundaries and exact rebased ranges. Six focused tests pass; no raw source values or copied bodies are retained in the result.

## 2026-10-09 — Serialize native image decodes to reduce measured peak memory

- Default the shared native decode admission to one active call. Preserve source/output/cache budgets and cancellation-owned leases. All ten admission and lease-lifetime tests pass alongside the document checks. The matched cold two-image experiment supports a 48.7% sampled peak reduction at about 32 ms median latency cost; the 100 MiB all-work target remains unmet.

## 2026-10-09 — Specify explicit diagram fence identity

- Add six regressions for adjacent, empty and unsupported fences, bounded attempts and metadata, malformed ranges and notebook composition. RED compiles and reproduces ten identity/selection issues.

## 2026-10-09 — Specify bounded code-body syntax tokens

- Add six regressions for canonical language profiles, exact safe UTF-16 ranges, cumulative scan/token budgets and malformed boundaries. RED compiles and reproduces 13 missing-token/budget issues.

## 2026-10-09 — Specify single native image admission

- Add causal continuation-barrier coverage for the default native image gate, including cancellation that retains its lease until native return. Existing intentional two-holder controls now select capacity two explicitly. RED compiles and fails eight default-capacity assertions across two cases.

## 2026-10-09 — Add native copy buttons beside visible code cards

- Place localized native copy buttons only in clear outside-card margins, indexing visible bodies on scroll. Controls retain revision targets, disappear on narrow layouts or lifecycle changes, preserve text/focus, and pass Space/Escape to the host.
- All 21 focused geometry, native margin and exact-copy tests pass. Correct one test to distinguish the expected Source-mode announcement from a stale copy action; actual RTL host and VoiceOver observation remain separate gates.

## 2026-10-09 — Specify native code-copy margin actions

- Add seven offscreen native TextKit regressions for outside-card placement, narrow layouts, private exact copy, stale actions, lifecycle cleanup, visible-only scrolling and host keyboard handling. The RED implementation compiles and reproduces six missing-control failures; narrow layouts already pass.

## 2026-10-09 — Place code-copy controls only in clear margins

- Validate code-body metadata once and use a bounded visible-range index for control candidates. Require a complete 22-point button inside a 32-point clear margin outside the reading column, rejecting offscreen and nonfinite geometry.
- All six focused geometry and indexing regressions pass on the Mac, including both semantic sides and 10,000-body late-viewport lookup.

## 2026-10-09 — Specify visible code-copy margin geometry

- Add six pure geometry/index regressions for complete outside-column buttons, narrow/offscreen/nonfinite rejection, exact body identity and a late viewport in 10,000 bounded bodies. After disambiguating CGFloat.infinity in the test setup, RED compiles and reproduces eight missing-placement/index issues.

## 2026-10-09 — Keep offloaded folder descendants metadata-only

- Recheck each opened directory component and enumeration boundary. A refused selected root remains unavailable; an inaccessible/offloaded optional child remains a partial metadata entry without a fabricated count. Regular offloaded children stay listable without content opens.
- All 29 selected-root, child and existing folder-listing tests pass, including descriptor/DIR cleanup before restoration, no-follow behavior, depth/entry budgets and unchanged owned source data.

## 2026-10-09 — Specify descendant-folder refusal and stream ownership

- Instrument existing descriptor-relative enumeration with native calls and real cleanup retained. Five new tests (18 cases) exercise child preflight/opened transitions, selected-root enumeration refusal, optional partial branches and dataless regular metadata.
- Combined with the selected-root suite, all 11 tests compile and RED reproduces 31 missing descendant/refusal issues. Cleanup accounting now includes every opened descriptor and transferred DIR owner, rather than only the selected root.

## 2026-10-09 — Pass scalar event flags across the monitor test queue

- The fresh Release experiment build exposed a concurrency warning in the deterministic monitor event seam. Capture the Sendable raw event value and reconstruct the Dispatch option set on its owning queue; production event handling remains unchanged.
- All 113 related tests in 17 suites pass without the warning. The premeasurement build and policy check were archived before any samples or warmups; the fixed image comparison plan remains unchanged.

## 2026-10-09 — Validate the resumed lifecycle checkpoint

- Clean `389ebcb` passes 3,486 parallel tests, six isolated timing checks, every native integration executable, all four host-source compiler groups and 22 static checks without skips (839 Swift files). Record the exact checkpoint and remaining stages in the implementation record and continuation plan.
- The owned materialized iCloud folder lists its offloaded child metadata while the child retains zero allocated blocks and unchanged size/mtime. This bounded observation does not replace partial-provider, signed-host or minimum-OS validation.

## 2026-10-09 — Guard selected-folder enumeration scope

- Wrap the complete synchronous folder parse in checked materialization refusal, with raw root preflight and authoritative opened/final descriptor flags. Capture native errors before cleanup; close the selected descriptor before policy restoration. Formats directly depends on the existing internal file-access module.
- All 24 selected-root and existing folder-listing tests pass. Child-directory traversal/refusal and complete DIR ownership tests remain the next stage; this root tranche does not establish those gates.

## 2026-10-09 — Specify selected-directory refusal and cleanup

- Add an internal immutable directory policy/probe around real root acquisition and cleanup. Six native tests (ten cases) compile and reproduce 26 missing scope/refusal issues, with cancellation and owned source-byte/metadata checks. Child traversal and DIR ownership are deliberately separate next-stage tests.

## 2026-10-09 — Record resumed lifecycle and provider evidence

- Update the implementation record and pending queue for production monitor/reloader/host integration, native code cards and the owned wholly-dataless iCloud observation. Preserve historical stop checkpoints and distinguish current local evidence from partial-provider, signed-host and minimum-OS gates.

## 2026-10-09 — Expose privacy-safe code copying in the native menu

- The rendered code-body context menu now retains a revision target and weak view, reusing the existing exact safe-copy policy and feedback. Unknown source labels never enter menu text; recognized finite language IDs use localized interpolation.
- All 19 focused code menu/copy/card tests in three suites pass, including all 14 language cases, stale actions and failed writes. Three control/help keys have complete draft translations and validated generated resources; native-speaker and host review remain open.

## 2026-10-09 — Specify code-block context-menu actions

- Add named menu/title seams and six native tests, including 14 language cases, actual retained menu actions, exact private copy, stale replacement/finding policy and failed-write behavior. After correcting the immutable parameter table isolation, RED compiles and reproduces 38 missing-menu/title issues.

## 2026-10-09 — Clear terminal extension reload hints

- Keep the visibility rearm hint only after a successful watch. A terminal reload clears it after applying the result; ordinary temporary hiding retains successful eligibility.
- Three deterministic actual-controller checks pass, covering both preview/result refusal forms, settings failure, disabled reload, explicit retry and normal hide/show. This is offscreen native integration, not signed Finder observation.

## 2026-10-09 — Specify extension visibility rearm eligibility

- Compile the actual preview controller in an isolated native integration executable with an injected monitor-start boundary. RED reproduces failed-start and terminal-reload visibility rearming; ordinary hide/show recovery remains a passing control. No signed Finder behavior is inferred.

## 2026-10-09 — Require a new request after companion monitor-start failure

- Retain a private per-request failed-start latch. Visibility, appearance and reload-switch changes cannot retry it; an explicit new content request resets eligibility and can successfully watch again.
- Both deterministic actual-session integration checks pass, including unavailable-content eligibility, source/request preservation, explicit recovery, monitor shutdown and unchanged synthetic file bytes. No user settings or cloud source is used in these checks.

## 2026-10-09 — Release refused live reloads before displaying them

- Unavailable source bytes are no longer watchable. A non-watchable preview/result releases its monitor before the host applies it, while final events still deliver one last guarded result.
- All 107 related refusal/monitor/live-reload tests in 16 suites pass. Generation and cancellation guards prevent late refusal from stopping a replacement watch; watchable repairable failures retain existing behavior.

## 2026-10-09 — Specify reload refusal and stale-result behavior

- Add an internal watch/event factory and read-only task completion snapshot for deterministic tests, preserving the public concrete monitor composition.
- Ten tests (16 parameterized cases) compile; RED reproduces 15 refusal/release semantic issues while stale generation, replacement, stop/lifetime, watchable cure and final-event controls pass. No wall-time waits or provider operations are used.

## 2026-10-09 — Specify companion monitor retry eligibility

- Add a narrow injected start boundary and read-only request-task snapshot to the actual companion session, plus a deterministic isolated integration executable using owned synthetic files.
- The Mac RED executable compiles and reproduces both missing behaviors: visibility/appearance implicitly retries a failed monitor start, and unavailable content starts monitoring. It uses no polling or user preferences; explicit new-request recovery and unchanged source bytes are also asserted.

## 2026-10-09 — Render continuous native code cards

- Apply one fresh native text block per explicit safe code body across its paragraph-style runs. Preserve foreign/quote blocks, fonts, syntax ink, paragraph geometry and exact text; restyling never mutates retained prior blocks.
- All 49 related native tests in seven suites pass, including actual card pixels through blank lines, narrow LTR/RTL-containing wrapping, adjacent separation, appearance changes, Source removal and exact selection/private copy. No new parser, source I/O or preference schema is introduced.
- Copy controls, bounded highlighting, remaining document improvements and large-document/real-host measurements continue separately.

## 2026-10-09 — Specify native whole-code card rendering

- Add five native regressions for continuous card pixels through blank paragraphs, adjacent-body separation, narrow LTR/RTL-containing wrapping, nonmutating appearance passes and exact font/selection/private-copy behavior.
- Correct two draft test setup issues before RED: initializer argument order and a missing combining-accent search token. The resulting Mac run compiles and reproduces six missing-card semantic issues. No production card styling is connected yet.

## 2026-10-09 — Compile the native code-card wrapper

- Add the narrow NSTextBlock wrapper for one explicit code body, using full content width, 8 pt padding and the accepted 7% palette-foreground tint. Apple documents backgroundColor from macOS 10.0; existing edge/width APIs match the quote wrapper.
- PreviewRenderers compiles successfully on the Mac before styling integration. The wrapper is unused until the following test-first card tranche.

## 2026-10-09 — End monitoring when materialized access is refused

- Check current descriptor availability before reporting modification; end through the existing revoked event on refusal. Every reopened owner uses the same guarded factory, and unavailable content ends immediately instead of scheduling retries.
- All 97 refusal/related live-reload tests in 14 suites pass, including real registration cancellation and manual queued retry controls. Correct the shared test probe’s leak assertion to compare descriptor multisets: independently owned failed reopens legitimately close before the old Dispatch registration. Successful-close and explicit lifetime assertions remain.
- Reloader/host rearming, directories and actual provider observations remain separate integration steps.

## 2026-10-09 — Specify guarded monitor events and reopening

- Resume the three immediate workstreams at the user’s request. Route initial and replacement event descriptors through the tested owner, retaining each owner until its Dispatch cancellation handler runs.
- Add deterministic queued event/manual-retry seams and six tests (11 parameterized cases). The Mac RED run compiles and reproduces 16 semantic issues for missing current-owner refusal and terminal unavailable reopening; existing retry/stop/order controls pass.

## 2026-10-09 — Record final checkpoint and stop development

- Record monitor-owner RED/GREEN/Release evidence separately from its uninstalled production-monitor integration. Refresh the pending queue with already completed full/signed checks without closing host gates.
- Preserve the failed `5284690` native cache attempt: correct nil/refusal replacement fails the bitmap-only validator, and warm request multiplicity also varies. No serialized comparison or memory-policy change is accepted.
- Record the user’s stop request and ignored monitor/code-card/measurement handoff paths. Further implementation or experiment execution waits for a later request.

## 2026-10-09 — Guard the owned event descriptor boundary

- Acquire a complete monitor descriptor owner inside one checked refusal scope, with raw no-follow preflight, authoritative descriptor flags, immediate errno mapping and cleanup on acquisition or restoration failure. Rechecking and closing share a lock; close is idempotent.
- RED `91ae28a` reproduces 52 semantic issues in nine tests; GREEN passes 40 related Debug tests and all nine owner tests in optimized Release. All 22 static checks pass without skips (823 Swift files). The helper remains unconnected to the production monitor; Core/event/rearm integration is preserved as a separate uninstalled draft.

## 2026-10-09 — Specify owned monitor refusal and cleanup

- Extract a narrow internal event-descriptor owner with the prior unguarded acquisition behavior and add nine tests (17 parameterized cases) covering refused availability, checked scope entry/restoration, authoritative flags, local cleanup, owner lifetime, symlink/FIFO rejection and idempotent close.
- The Mac RED run compiles and reproduces 52 semantic issues before adding refusal safeguards. The helper is not yet connected to the production monitor; integration and event/reopen tests are a separate tranche.

## 2026-10-09 — Validate classification and safe-copy integration

- Clean `9134675` passes 3,444 parallel tests, six isolated timing tests, all native integration executables, package/four-host compilation and all 22 static checks without skips (821 Swift files). This supersedes the earlier failed full run after the PGP fixture repair.
- Refresh the continuation plan and evidence record; distinguish the latest local checkpoint from the earlier hosted and signed artifacts. No Finder, provider, accessibility or memory gate is closed.

## 2026-10-09 — Record classification, signed bootstrap and safe-copy evidence

- Record classifier refusal/control results, the real isolated policy check, signed extension bootstrap artifact and 33 bundle-language cases. Preserve the failed full-run PGP test and focused fixture repair evidence.
- Update plan and pending host observations for exact code bodies and revision-bound copy; leave UI, monitor/directory, provider and performance acceptance open.

## 2026-10-09 — Resolve code-copy actions against current safe content

- Propagate explicit code-body metadata into the native text owner and bind copy targets to its revision. Replacement, findings/mode/state changes and suspension invalidate retained actions; appearance-only restyling preserves current targets.
- Copy validates membership and bounded UTF-16 ranges against the current rendered document, then reuses whole-document Tag sanitization, the injected private writer and existing success feedback without changing selection or storage.
- All 61 focused/related native tests in eight suites pass. This is the safe action service; context-menu/margin controls, card styling and bounded highlighting remain separate.

## 2026-10-09 — Specify generation-bound native code copy

- Add a small internal target/action seam and eight native private-pasteboard tests for exact concealed code, Unicode Tags, identical/canonical replacement, findings changes, writer failure, selection preservation, appearance-only reuse and mode/suspension lifetime.
- The Mac run compiles and reproduces eight missing-target failures before implementation. No context menu, margin button, card style or new strings are introduced in this checkpoint.

## 2026-10-09 — Keep the PGP routing regression independent of missing files

- The full 3,436-test package run found one stale markup test using a nonexistent .asc path. Guarded classification now reports missingFile before the injected reader, so that setup no longer tests unsupported markup routing.
- Replace it with an owned synthetic .asc fixture and explicit absent type metadata, retaining unsupportedFormat, zero reads and unchanged source bytes. This avoids installed-app UTType assumptions. All 26 markup/classification tests pass; the failed full run is retained before the next integration pass.

## 2026-10-09 — Refuse materialization before extension request work

- Both Quick Look request entrypoints set the checked process-wide refusal policy before preferences or source work. Failure returns the existing unavailable preview or content-free thumbnail glyph without starting a reader; raw I/O boundaries retain their thread scopes.
- Link PreviewFileAccess directly from both extension targets and enforce that graph in project validation. Package/four-host source compilation and the full project/resource check pass.
- Signed bundle and real provider behavior remain separate checks; this does not close Q153 while monitors, directories and provider observations remain.

## 2026-10-09 — Verify real materialization policy in a disposable process

- Add a standalone native integration check for repeated process refusal, nested synchronous thread scopes and restoration after a thrown body. Its process exits after the check; no provider file or user preference is touched.
- The Mac executable passes against the existing checked wrapper before host wiring. Add it to the native test entrypoint; this verifies Darwin policy calls, not actual Finder/provider no-download behavior.

## 2026-10-09 — Guard fallback file-type metadata lookup

- Enclose unknown local-path classification in the checked synchronous refusal scope, with raw flags/kind checks before and after optional content-type lookup. Preserve files/directories and refuse symlinks/nonregular inputs without following them.
- Map direct or bounded wrapped materialization refusals before restoration. Preserve known-name fast paths and ordinary optional lookup failures; unavailable inspection reaches the existing content-free thumbnail fallback before content work.
- All 131 focused/related tests in 16 suites pass, including real local directory/extensionless controls. Path metadata and scoped Foundation lookup do not prove File Provider no-download behavior; process bootstrap and other I/O boundaries remain open.

## 2026-10-09 — Specify classification compatibility and thumbnail fallback

- Add nine controls for materialized type lookup, directory/extensionless routing, alias and disabled-type fast paths, ordinary optional errors, nonregular files, cancellation and invalid budgets. Exercise the real missing-unknown thumbnail path without adding a service seam.
- The Mac run compiles and reproduces 22 semantic issues before the classification fix. Keep errno fault mutation confined to synchronous refusal tests.

## 2026-10-09 — Specify guarded file-type classification

- Extract the existing alias-first optional type lookup behind a request-local internal seam. Add typed unavailable inspection and map it to the existing content-free thumbnail fallback.
- Four Mac-compiled refusal tests reproduce 40 semantic issues before guarded metadata integration, covering dataless flags, native/wrapped refusals, policy failures and zero downstream reads/factories. Ordinary classification behavior is preserved in this test checkpoint.

## 2026-10-09 — Record integrated reader/document and scheduler checks

- Clean 9b6fc9d passes 3,416 parallel tests, six isolated timing tests and every native integration executable, including 148 contrast ratios and 648 adversarial cases.
- Record the verified scheduler cancellation/delivery events and the later passing package/four-host compiler check. Update the continuation plan without closing provider, host, copy-control or performance gates.

## 2026-10-09 — Attribute image cancellation and final delivery

- Emit optional read-only events beside existing cancellation decisions and immediately before the unchanged delivery branch. Keep cancellation requests, task cancellation, current generation, result presence and callback invocation distinct.
- All 44 focused scheduler/admission/native-page/lifetime tests in six suites pass. The events enable causal measurement; they do not change image policy or establish an accepted footprint result.

## 2026-10-09 — Specify image cancellation and delivery observations

- Add optional internal event types and seven continuation-gated tests that distinguish scheduler cancellation requests, late cancellation, stale generations, nil results and actual callback eligibility. Events carry no bitmap values.
- The Mac run compiles and reproduces 13 semantic issues before event emission is wired; the default nil-observer control passes. Production scheduling, cancellation and delivery behavior remain unchanged.

## 2026-10-09 — Record random-read and code-body validation

- Update the continuation inventory, pending host observations and implementation evidence for the guarded random-access reader and exact whole-code metadata. Keep provider, native copy/card UI and host/performance gates open.

## 2026-10-09 — Record exact rendered code-body boundaries

- Markdown and the shared block writer now record bounded whole-body UTF-16 ranges from their actual emission boundaries. Preserve text, per-line decorations, blank lines and notebook composition; keep separators, labels and truncation notices outside each range.
- Retain only canonical typed language hints from bounded ASCII tokens, checked before case conversion. Unknown, overlong and hostile labels stay inert. No copy controls, cards or source I/O changes are included.
- All 186 focused/related renderer tests in 16 suites pass on the Mac, including quote pixels, exact ranges and notebook truncation.

## 2026-10-09 — Specify explicit whole-code body metadata

- Add an internal default-empty code-body range model and 11 tests for exact rendered UTF-16 boundaries, blank lines, adjacent/unterminated fences, finite language hints and notebook composition/truncation. No copy controls or presentation changes yet.
- The Mac run compiles and reproduces 24 semantic issues against emitters that do not yet record whole-code metadata.

## 2026-10-09 — Guard random-access file ownership and reads

- Construct the complete descriptor owner inside the checked synchronous refusal scope, and scope every valid range read with fresh dataless flags and snapshot validation. Capture native errors before restoration; release partial owners and restoration failures without leaking descriptors.
- Preserve cumulative charging, overlapping reads, cancellation, EINTR handling and mutation refusal. As with complete reads, raw guarded availability replaces the Foundation iCloud-status heuristic.
- All 50 focused/related Debug tests and all 12 optimized Release random-access tests pass. All 22 static checks pass without skips; provider/Finder, classification, monitor, directory and extension bootstrap integration remain open.

## 2026-10-09 — Record hosted validation and rejected cache measurement

- Full hosted static/macOS run 37904351897 passes the synchronized 1c5747d checkpoint, including the October 9 additions.
- Preserve the failed native cache/draw attempt and its ordinary layout-replacement diagnosis. No serialized comparison ran, no cache pair is accepted, and no production memory budget changes.

## 2026-10-09 — Specify guarded random-access ownership and reads

- Add 12 tests for construction refusal, descriptor ownership through policy restoration, per-range flags and errno, cumulative charging, cancellation and source mutation. Fixtures and fault controls remain request-local.
- The Mac run compiles and reproduces 48 semantic issues in three suites against the unchanged random-access implementation. No provider or Finder acceptance is inferred.

## 2026-10-09 — Verify the signed resumed build

- Clean 67da062 builds, passes app/extension signature verification and launches the companion. The unchanged Xcode graph resolves the new file-access module through PreviewCore.
- All 33 explicit language/fallback cases pass across three signed bundle contexts at 1,082 keys each. Record the 177-file artifact manifest; keep actual Finder/provider/VoiceOver, minimum-OS and release acceptance separate.

## 2026-10-09 — Recognize the audited file-access package product

- The separate project check caught its old seven-product allowlist after PreviewFileAccess was added. Include that explicit product in the inventory and clarify the diagnostic; all unknown exports still fail validation.
- The corrected full project check passes: four targets, both extensions, CAD service graph, manifests, 1,082 keys in 14 locales, 76 samples and app icons. PreviewCore supplies the module transitively; direct host process-policy imports and their graph changes remain later Q153 bootstrap work.

## 2026-10-09 — Validate the integrated resumed checkpoint

- Clean 3e6e1b2 passes 3,393 parallel tests in 369 suites, six isolated timing tests, every native integration executable, 148 contrast ratios and 648 adversarial cases.
- The package and four host-source compiler groups pass; all 22 static checks pass without skips, including syntax coverage of 807 Swift files. Record this as local integration evidence while preserving signed-host, provider, minimum-OS, accessibility and performance gates.

## 2026-10-09 — Record quote and reader integration evidence

- Update the plan, continuation inventory and Mac observation queue with the passing quote-styling, complete/leading-reader and scheduler-attribution tranches.
- Preserve explicit remaining random-access/provider, whole-block document, image measurement, signed-host, minimum-OS and accessibility gates. No release acceptance checkbox changes.

## 2026-10-09 — Attribute image measurements to scheduler generations

- Add optional internal read-only scheduling events and a contextual decode callback using the existing generation UUID. Normal decoding remains the default; measurements can distinguish identical concurrent page payloads and capture geometry when requests are scheduled.
- All 35 scheduler, admission and native page tests pass, including the six causal continuation-gated regressions. No decode/admission/cache budget changes and no new accepted footprint measurement are implied.

## 2026-10-09 — Specify causal image-request measurement hooks

- Add internal API-only scheduling observation/contextual decode seams and six continuation-gated tests. Preserve the default decode path while reproducing missing per-generation attribution for identical payloads, replacement, reprioritization and queued cancellation.
- The Mac run compiles six tests and reproduces five semantic issues; the nil-instrumentation control passes. No image policy or benchmark outcome changes in this test checkpoint.

## 2026-10-09 — Guard complete and leading file reads

- Enclose complete/leading source I/O in the checked synchronous refusal scope. Replace Foundation metadata lookups with raw lstat preflight, authoritative fstat and final dataless-flag checks; map native errors before restoration and always close acquired descriptors.
- Preserve byte limits, no-follow/nonblocking open, cancellation, SQLite locks and all three sidecar passes. Fully materialized files are no longer refused solely for stale/non-current iCloud downloading-status metadata.
- All 25 focused reader/adversarial/input tests and two directory/symlink/FIFO/mesh controls pass on the Mac. Existing default-reader controls execute the real thread-policy wrapper on owned local files. Random-access, monitor, directory, classification and host boundaries still await integration; actual provider no-download proof remains open.

## 2026-10-09 — Specify bounded-reader safety controls

- Add seven control tests for whole-scope byte limits, entry/restoration failure, EINTR retry, SQLite sidecar/lock ordering, sparse bytes and expired/cancelled requests.
- The Mac run compiles and reproduces 15 semantic issues in the new suite before integration. These tests use owned local fixtures and injected policy faults; existing cancellation/deadline controls remain exercised without wall-time waits.

## 2026-10-09 — Reproduce missing bounded-reader dataless checks

- Add internal policy/probe seams without changing source I/O, plus synthetic complete/leading refusal, authoritative descriptor, cleanup, errno and final-flag regressions.
- The Mac run compiles five tests with eight parameterized cases and reproduces 20 semantic issues against the old reader. No source flags are changed and no provider file is accessed.

## 2026-10-09 — Render native quote bars and prose emphasis

- Apply native quote blocks with a 3 pt directional bar and font-scaled padding; preserve paragraph indents, heading/code roles, foreign blocks and exact safe text. Bold and italic use body ink.
- Native pixel checks caught NSTextBlock's zero-width default; explicitly fill the reading column. Controlled bitmap tests now verify visible LTR/RTL bars, narrow wrapping and no ink outside the column without relying on the display's color profile or bidi advance rectangles.
- All 98 focused/nearby tests in 12 suites pass, including six Q72 regressions, source restoration, selection and private-pasteboard copy. Signed-host, macOS 15, VoiceOver and large-document layout performance remain unverified; wider code/alert/table block work remains open.

## 2026-10-09 — Correct stale source-work inventory

- Reconcile eleven continuation-plan rows against recorded implementation and test evidence: renderer extraction/contracts/palette, worker and host diagnostics, accessibility transitions, reading/reflow, camera retention, value-free thumbnails and generator retirement.
- Mark their source deliverables present while retaining every applicable host, accessibility, performance and release observation. This prevents already-implemented work from appearing as missing implementation; it closes no acceptance checkbox.

## 2026-10-09 — Reconcile resumed work and hosted validation

- Record the user's renewed development instruction while retaining the October 8 stop as history. Full hosted static/macOS run 37899995290 passes compact-header checkpoint e798e9c.
- Record the isolated Q153 tests, in-progress Q72 native integration and rejected Q154 cache/draw attempts. Keep provider, signed-host, minimum-OS, accessibility and memory acceptance open.

## 2026-10-09 — Compile a narrow native quote-border wrapper

- Add an app-owned NSTextBlock wrapper using the macOS-15-compatible NSRectEdge APIs. Direction changes create a fresh block rather than mutating shared paragraph references.
- The PreviewRenderers target compiles on the Mac. The wrapper is not applied yet; pixel/layout and host validation remain pending.

## 2026-10-09 — Reproduce rendered quote and emphasis gaps

- Add six native regressions for prose emphasis colors, quote bars, nested and RTL paragraph isolation, inert markup composition, exact safe text/selection/copy and Source restoration.
- The Mac run compiles and reproduces 28 semantic issues against unchanged rendering, including absent bars in actual TextKit pixels. No renderer behavior changes in this test checkpoint.

## 2026-10-09 — Implement isolated dataless policy wrapper

- Implement checked Darwin process refusal and synchronous thread policy scopes, restoring the previous policy after successful and throwing operations. Restoration failure refuses the result and releases its owned resources; native errors must be mapped inside the scope.
- All 14 deterministic tests pass in Debug and optimized Release on the Mac, including nested failures, owned-result cleanup and errno preservation. Consumers remain unchanged; real provider access, no-download behavior and extension integration remain unverified.

## 2026-10-09 — Reproduce missing dataless file-access policy

- Resume the quality program on the user's new instruction. Add an isolated PreviewFileAccess product/target depending only on PreviewContracts, with API-only stubs and 14 deterministic policy tests; existing consumers are unchanged.
- The Mac run compiles and reproduces 33 semantic issues for flag/refusal mapping, process and nested thread policy, restoration failures, owned-result lifetime and errno preservation. These fake-driver tests perform no real policy syscall or provider access; no no-download claim is made.

## 2026-10-08 — Complete compact-header validation and stop development

- Clean `3862820` passes 3,355 parallel package tests, six isolated timing tests, every native integration executable, 148 contrast ratios and 648 adversarial cases. The unchanged production sources pass all four host-source compiler groups; 22 portable checks pass with zero skips.
- Reconcile the compact-header plan and pending signed-host observations. Record the limited Q152 runtime/object/ASan-canary success and its failed parser-PC reachability gate without claiming a fuzz run.
- Honor the user's requested stop after current validation and PR synchronization. Preserve Q154/Q153 drafts and the Q72/Q73 review for later; begin no new implementation or measurement.

## 2026-10-08 — Keep renderer regressions on the facade mode control

- The full compact-header run exercised 3,355 package tests and exposed three stale assertions: a breadth-first lookup selected the References style control, and a badge test compared the nested mode control's local frame to its host.
- Use the existing named facade mode seam in the affected tests and every remaining lookup intended for that control; preserve labels, counts, actions and internal References-style assertions. Convert badge alignment checks into host coordinates. The two reproduced suites pass all 17 focused tests; full integration follows this correction. Production behavior is unchanged.

## 2026-10-08 — Integrate compact native mode selection

- At compact density, replace the segmented control with a native pull-down containing the same ordered capabilities, current selection and existing shortcut hints. Preserve one typed dispatch path, refuse stale menu items, transfer control focus on resize and forward closed-control Space/Escape to the host.
- Hide the source gutter in compact density without changing its saved setting; restore only eligible source gutters. Resize uses cached layout state and preserves text selection and viewport without reparsing or restyling source. Existing two-fact compact behavior remains.
- All 152 focused tests in 32 suites pass after fixing initial accessibility labels and restoring the pull-down title's inert state after AppKit menu installation. Layout assertions now compare nested controls in a common coordinate space and use the visible control for compact geometry. Full integration follows; the 480 pt threshold and 24 pt hysteresis remain provisional, and signed-host, VoiceOver and future rail behavior are not accepted by this checkpoint.

## 2026-10-08 — Reproduce missing compact mode and gutter behavior

- Add API-only mode-control seams and 12 native tests covering the complete compact menu, stable mode order, current selection, stale-item refusal, host keys, focus transfer, gutter visibility, one-row facts and resize without source/model work.
- The Mac run compiles and reproduces 53 semantic issues across two suites against the existing segmented-only behavior. The density threshold remains the existing unmeasured placeholder; no host measurement or production compact behavior is claimed by this test checkpoint.

## 2026-10-08 — Observe information in the signed companion and Finder

- Build, signature-verify and launch clean `3a97e4f`; all 33 explicit resource-language cases pass across three signed bundles with 1,082 keys. The exact source also passes full hosted static/macOS run 37818484024.
- Observe facts and inline information in the companion sample and synthetic JSON Finder pane/panel, including native scrollbar control and mode-sensitive help. A fresh JSON Lines pane clears the old disclosure. All 83 synthetic fixture hashes remain unchanged; update only observed matrix cells and their exact-artifact regression inventory, then regenerate the website projection. Wheel delivery, child-focused keys, VoiceOver, measured density and wider host/release coverage remain open.

## 2026-10-08 — Validate information integration and reconcile the remaining plan

- Clean `bfcb7c1` passes 3,342 parallel package tests, six isolated timing tests, every native integration executable, 148 contrast ratios, 648 adversarial cases, host-source compilation and all 22 portable checks with no skips.
- Reconcile the facts, limits, information, privacy/copy and measurement rows to their actual evidence. Correct the stale nightly-fuzz proposal to the accepted manual Mac CI policy and record the failed compiler pilots without claiming fuzz execution. Finder, VoiceOver, language review, image footprint and release gates remain open.

## 2026-10-08 — Make scheduler-cap coverage causal

- The full information-panel run exercised 3,342 tests and failed one existing five-second scheduler polling assertion under shared-suite load. The same seven scheduler tests passed in isolation; no production scheduling failure was reproduced.
- Replace that test’s polling with held decode and delivery continuations. Assert exact initial admission, all ten unique deliveries, the concurrency cap and a drained scheduler. Observe priority at admission rather than inferring it from asynchronous completion order. The initial repair passed 16 focused tests; full validation of the final admission assertion follows this commit. Production behavior is unchanged.

## 2026-10-08 — Wire bounded inline preview information

- Integrate the information panel below notes and above findings, capped at one quarter of the safe area. Populate on open, retain state during same-document restyles/modes, clear on new generations/states, preserve the facts row, and announce only the user's final disclosure action.
- Help and dispatch share capabilities of the installed surfaces; no duplicate mode table, source access or eager Profile work is added. Final geometry show/resume/failure callbacks refresh available help. The lead shares ownership of that narrow geometry integration boundary.
- All 193 focused native tests pass across 25 suites. Tests exposed native button alignment overflow and scroll-view focus forwarding; the borderless button now has its actual 22 pt hit box and the scroll view retains focus until safely returned. The legacy badge expectation uses its stable button label, and the narrow-height check now measures an actual TextKit line instead of a fixed 24 pt assumption. Independent source review found no additional actionable defect; full integration and signed-host/VoiceOver checks remain separate.

## 2026-10-08 — Add the native information components

- Add a capability-only command policy, localized app-owned provenance formatter and bounded inline scroll component. The 22 pt native disclosure button and scroll view forward Quick Look's reserved keys, and static information rows avoid a secondary field editor. The existing copy/zoom chip is unchanged.
- The components compile on the Mac and all nine capability/copy tests pass in two suites. Facade wiring and the remaining disclosure/layout/focus regressions follow separately; this is not host acceptance.

## 2026-10-08 — Reproduce missing inline preview information

- Add API-only empty seams and 23 native tests covering the real disclosure button, safe local provenance, current command capabilities, lifecycle clearing, bounded scrolling, visible first row, geometry failure, focus and host-reserved keys. The Mac run compiles and reproduces 28 semantic issues across five suites before implementation.
- Add five contextual messages, including a plural count, through the localization tool for all 14 draft languages and assign the new component ownership. Translation review and real Finder/VoiceOver validation remain separate.

## 2026-10-08 — Measure serialized image decoding

- Paired Release runs at clean `058335a` retain identical 8 MP output and source/build/fixture fingerprints across 112 samples. Capacity-one admission cuts the 16 MP pair's maximum incremental footprint roughly in half, while median request time rises 76% cold and 96% warm; single-image peaks remain unchanged.
- Every heavy scenario still exceeds the 100 MiB target. Preserve the source-only experiment and complete hash-checked raw evidence; production admission remains unchanged pending actual draw/cache evidence.

## 2026-10-08 — Validate the integrated facts header

- Clean `a73ac03` passes 3,319 parallel tests in 356 suites, six isolated timing tests, every native integration executable, 148 contrast ratios and 648 adversarial cases. Full companion/extension/CAD-service source compilation and all 22 portable checks pass with no skips.
- Record the earlier hosted full success at `36ed46c`; actual signed Finder, VoiceOver, minimum-OS and reviewed-language evidence remains separate.

## 2026-10-08 — Keep appearance assertions tied to the status notice

- The full Q52 run exercised 3,319 tests and found one stale hierarchy lookup with two assertions: the new facts field was mistaken for the status notice. Use the named status seam while preserving both fallback-wording and contrast checks; production behavior is unchanged. Full verification is rerun after this test correction.

## 2026-10-08 — Keep carried-image counts conservative

- Mark fallback carried-image counts as lower bounds because cover-only and bounded collections are not exhaustive. Explicit parser totals retain priority and single-image pixel facts remain unchanged.
- All 110 focused Q52, notebook-figure, EPUB and comic tests pass in 13 suites. Record the completed cached-facts implementation and focused evidence while retaining full integration, real-host layout/VoiceOver and language-review gates.

## 2026-10-08 — Reproduce non-exhaustive embedded-image counts

- Independent review found that cached images can be only an EPUB cover or a bounded notebook/comic subset. A native model/formatter regression reproduces two exact-looking count failures while confirming that adapter-supplied exhaustive totals retain priority. Pixel metadata is unaffected.

## 2026-10-08 — Keep fact templates visible to localization validation

- Replace dynamic resource dispatch with literal typed format calls, preserving shared count formatting and every existing output. Normalize two Hausa glottal stops through the repository's typography tool.
- All 22 portable checks pass with no skips, including localization tests and exact resource references; 21 focused formatter/partial-count/header tests pass in three native suites. No validator exception or parser baseline is widened.

## 2026-10-08 — Reject ineffective image subsampling

- At clean `36ed46c`, paired Release production/factor-two runs each recorded 56 samples with identical source/build/executable/fixture identity and bitmap geometry. The hint produced no meaningful memory benefit; some JPEG lifetime peaks increased. Production behavior is unchanged and the 100 MiB target remains unmet.
- Preserve raw reports, experiment sources, validation logs and distributions in a hash-checked source-only archive. Serialized decoding at unchanged 8 MP is the next independent experiment; actual drawing/cache and host measurements remain separate.

## 2026-10-08 — Keep partial record and node facts honest

- Add defaulted lower-bound provenance to record/node facts and format it through the existing localized marker. Cached JSON Lines records, subtitle cues and outline nodes from known source prefixes no longer look like complete-file counts; complete counts and all existing constructors stay compatible.
- All 367 focused facts, parser, subtitle, INI and thumbnail checks pass in 57 suites after updating every associated-value match, including the thumbnail JSON classifier. The new geometry check also confirms that only typed read-boundary sizes reach its header.

## 2026-10-08 — Reproduce exact-looking counts for partial text

- Three Mac regression tests reproduce three misleading counts: JSON Lines records, subtitle cues and cached outline nodes from a known source prefix lack their lower-bound marker. Complete-file counts and typed geometry source-size propagation pass in the same run.

## 2026-10-08 — Retain notebook counts with the rendered plan

- Return the existing notebook Plan's total cell count with its safe rendered document, including empty cells and cells beyond the rendering prefix. Keep the old render API as a forwarding entrypoint and cache the typed count beside the document; header facts do not reparse JSON.
- All 171 focused notebook, facts and remaining-mode privacy canary checks pass in 19 suites. Invalid, oversized, deeply nested, node-limited and unrenderable documents do not invent counts; decoration bisection preserves the full validated total.

## 2026-10-08 — Reproduce missing notebook cell facts

- Six Mac tests reproduce 12 missing-count issues through existing cached-model and native-header seams. They distinguish total notebook cells from shown blocks, exercise decoration bisection and rendering limits, and reject invented counts for malformed, oversized and unrenderable input.
- The implementation will retain the existing parse/plan count with its rendered document; metadata must not trigger another JSON parse.

## 2026-10-08 — Carry source sizes from existing read results

- Attach complete or explicitly partial size facts to non-text summaries/conversions and geometry at their existing read boundary. Random-access sizes retain Int64 precision without reading contents; URL/directory summaries gain no invented zero. Parser-supplied facts retain priority, and source-text compatibility is unchanged.
- All 184 focused pipeline, facts, geometry, partial-input, grid and thumbnail checks pass in 34 suites. Reader spies verify no extra content/metadata read and no disabled-type access.

## 2026-10-08 — Reproduce missing read-boundary size facts

- Add an additive geometry-facts field with an empty compatibility default and source-reader spies for complete/partial binary data, Int64 random-access metadata, directory summaries, geometry and disabled requests. Nine Mac tests compile and reproduce four missing-size issues; existing parser-facts and disabled-read guarantees pass.
- The next change supplies non-text sizes from the existing read result, never from a summary's legacy byte-count sentinel or an extra metadata/content read.

## 2026-10-08 — Show cached facts in the native header

- Put facts before the mode control in the existing single row, with middle truncation, the full tooltip/accessibility value and four/two scalar budgets. Cache family facts per presentation, reformat on density/locale changes, and clear metadata for every no-content state and replacement. Notes remain below the stable row.
- All 128 focused facts/chrome/reload tests pass in 12 suites. Migrate older tests to named status/facts controls and AppKit alignment rectangles while preserving geometry, reading-order, chip, lazy-Profile and replacement assertions. Actual Finder density and VoiceOver gates remain open.

## 2026-10-08 — Supply localized facts from cached safe models

- Implement family providers using typed parser facts and already-built table, listing, outline, MIDI and image metadata. Generated summaries never reuse legacy text byte/line/encoding fields as file facts; Profile stays lazy, partial counts remain explicit and invalid numbers are omitted.
- Flatten grouped metadata before the four/two scalar display budgets. All 23 provider/formatter tests pass on the Mac after matching the existing MIDI formatter's padded duration (`02:05`). The locale-aware duration wrapper compiled against the macOS 15 target. Header integration follows separately.

## 2026-10-08 — Reproduce missing cached presentation facts

- Add typed pixel/image counts and capped geometry counts, cached-listing and empty provider/formatter/header seams, plus 24 messages in all 14 draft languages. Thirty Mac tests compile and reproduce 67 missing-facts issues before production integration; they cover metadata provenance, lower bounds, scalar display budgets, locale formatting, replacement and lazy Profile behavior.
- Full hosted static/macOS run 37807372902 passed at `36ed46c`, including package, source compiler and native integration checks. Signed-host and release acceptance remain separate.

## 2026-10-08 — Verify the unified limits and complete mode-canary checkpoint

- At `070c91b`, the full entrypoint passes 3,272 parallel package tests in 349 suites, six isolated timing tests, every native integration executable, 148 companion contrast ratios and 648 adversarial cases. All 22 portable steps pass with no skips; all 91 static-tool self-tests pass with no skips.
- The app, both extensions and CAD service source compiler checks passed at `7f5df79`; subsequent commits only integrate the portable image-validator step. Record the new Q51/Q155/Q151 checkpoint without closing memory, signed-host, minimum-OS, translation-review or release gates.

## 2026-10-08 — Run image-report validation on every portable check

- Add the image benchmark’s five adversarial validator tests to the shared portable gate used locally and in CI. The static-tool self-tests now pass all 91 cases without skips. Actual Release image measurement remains a separate Mac workload.

## 2026-10-08 — Require the image benchmark validator in the portable gate

- Extend the existing static-step inventory expectation to include the new portable image-report validator tests. The self-test suite reproduces the missing step with one failure among 91 tests and no skips; wire the validator into the gate in the next commit.

## 2026-10-08 — Keep the native clipboard check readable to the syntax gate

- The portable gate found tree-sitter’s known inability to parse `try #require` directly in a for-loop sequence, despite successful native compilation. Bind the same required type list before iterating; assertions and behavior are unchanged. The focused syntax check passes without widening the parser baseline.

## 2026-10-08 — Preserve inert notebook image placeholders

- Drop a privacy range only when all its original bytes lie within one already-omitted image value. Keep the existing exact offset mapping for adjacent text and every range crossing an image boundary; reuse binary search so many images/ranges remain bounded. Shared secret recognition and image extraction are unchanged.
- All 237 focused tests in 38 suites pass, including the ordinary padded PNG, complete text-only thumbnail, contained/adjacent/crossing boundaries, all mode canaries, Rows/References copy, notebook health/image budgets and hidden-content checks. The only compiler warning is the known native SwiftPM backend deprecation. Full integrated verification follows on this committed repair.

## 2026-10-08 — Extend native canaries and reproduce notebook placeholder concealment

- Add independent fixtures for environment summaries, subtitles, TAR listings, bibliography references, GeoJSON plots, Parquet samples, notebook pages and app icons. Together with the first tranche they exercise all 18 mode identities, actual copies, realized accessibility/tooltips, image captions, source replacement and byte/metadata immutability. Generic thumbnail policies prove zero reads/factories; explicit test-only policy changes inspect underlying safe scenes without changing shipping behavior.
- An ordinary padded PNG notebook with safe cell text exposes a real defect: a heuristic range inside omitted base64 maps to the inert `null`, which is then concealed into invalid JSON. Preserve that input; reject the temporary no-padding workaround. New boundary tests retain concealment for ranges crossing into adjacent text while requiring wholly omitted ranges to disappear.
- The 94-test, 24-suite Mac RED has exactly five expected notebook assertions; all Q155, collector and other Q151 cases pass. Metadata canaries establish text/label safety, not OCR or pixel redaction. Broader adapter families and signed-host surfaces remain open.

## 2026-10-08 — Share native copy policy in Rows and References

- Rows adopts the existing hosted-table services; References uses the shared TextKit 1 selection writer and forwards the facade’s private pasteboard, current Tag policy and once-only copy feedback. Failed or empty writes remain silent.
- All Q155 and clipboard-collector checks pass in the 80-test focused run. Inspect every advertised native format, including BOM-aware external/legacy UTF-16. Primary plain text and displayed storage retain exact code units; rich and derived formats must match an independent native writer, which documents AppKit’s canonical normalization rather than silently accepting it. Retain valid flags while removing detected unsafe Tag payloads.
- Extend the reusable canary collector to all native mode identities. Remaining-family fixtures are committed separately; an ordinary padded notebook image has exposed a placeholder-mapping regression that remains under repair.

## 2026-10-08 — Consolidate cached-model limits in the preview strip

- Move table, row-sample and partial-listing limits into the facade’s single bottom strip. Count the actual read batch, use exact CSV/TSV totals only for complete source reads, separate column/cell caps, and compute Profile facts only while Profile is selected. Inner table/tree notice bands are removed.
- All Q51 regressions and migrated table, listing, Profile and chrome assertions pass in the combined 256-test run. That run still reports seven separate clipboard-inspector/thumbnail-fixture issues; no full-suite or signed-host pass is inferred. Native test compilation succeeds on Xcode 27 / Swift 6.4.

## 2026-10-08 — Reproduce derived-mode clipboard wiring defects

- Seven native copy cases expose eight Rows/References integration failures through the real facade. Tests refuse to substitute the child’s clipboard or policy, and check exact displayed code units, all native clipboard representations, valid flags, failure/no-selection silence and once-only shared feedback.
- Add only an injectable successful-write result to the existing table copy path. Correct a test-only call that confused resource language with number-formatting locale before obtaining semantic RED evidence. Production Rows/References wiring follows separately.

## 2026-10-08 — Reproduce missing unified limit notices

- Add an empty cached-model notice seam and native regressions for partial listings, byte/cell/row limits, exact versus unknown totals, selected-mode isolation, Profile laziness, sorting/filtering and replacement. The combined Mac RED run reproduces 60 Q51 notice issues before implementation.
- Add four typed messages in all 14 draft languages and additional plural-template arguments. Three actual-resource tests pass, covering singular selection with a larger total, all resource sets and independent language/number formatting. Coverage is 1,053 keys and 11 plurals; translation review remains separate.

## 2026-10-08 — Measure and retain the image-memory shortfall

- Complete all seven Release scenarios at clean `293fcb2`, with 56 samples and 3,060 actual footprint probes. A single 40 MP PNG/JPEG exceeds 115 MiB incremental footprint; two 16 MP PNGs reach about 250 MiB. Oversized rejection stays below 5 MiB. The 100 MiB starting target remains unmet.
- Preserve raw fingerprints and measurements with their sampling, cancellation and process-scope limits in the image-footprint validation record. This evidence guides the next memory change; it does not close signed-host or minimum-OS acceptance.

## 2026-10-08 — Correct the image sampler callback isolation

- The standalone Release worker compiled but its first timer event trapped on a Swift concurrency queue assertion. The retained crash trace identifies MainActor inference in the sampler initializer’s dispatch callback. Mark the timer event and cancellation callbacks explicitly Sendable so they only capture thread-safe state/continuations on the sampling queue. Production decoding is unchanged; measurements restart after this repair.

## 2026-10-08 — Link only the objects emitted by the current build

- Prefer SwiftPM’s current build-description object list over its broader output map, retaining map/legacy fallbacks for older and Clang layouts. Missing active objects still fail instead of falling back to stale files.
- Both new regressions and four existing link-inventory tests pass. The actual Release build resolves 375 current objects; standalone image-worker compilation and measurement resume on this committed repair.

## 2026-10-08 — Reproduce Release object-inventory ambiguity

- The dedicated Release image build succeeds, but the standalone linker sees an inactive whole-module placeholder in SwiftPM’s output map. Two isolated regressions reproduce the missing-placeholder failure and stale per-source object inclusion when emission modes coexist. The current build description supplies the authoritative emitted object inventory.

## 2026-10-08 — Add the fingerprinted native image-footprint probe

- Add a Release worker that calls the production ImageIO decoder and admission gate, samples actual task-ledger footprint, and separates cold processes, warmed samples, held bitmaps, immediate reference release and kernel lifetime peaks. Complete synthetic image fixtures cover 40 MP PNG/JPEG, small-image pairs, mixed admission, oversized rejection, AVIF and cancellation/replacement.
- The report validator rejects missing measurements, inconsistent image outcomes and unsupported cancellation claims. Five portable adversarial test methods pass after the original draft failed 18 cases. Swift compilation and actual measurements follow on this committed harness; no memory target is claimed yet.

## 2026-10-08 — Confirm the synchronized checkpoint in hosted macOS CI

- Full hosted static/macOS run 37763205040 passes at `d7c5208`, including source compiler, package and native integration checks. Rerun only the overlapping cancelled static job; the macOS job passed on its first attempt. Update the PR evidence while retaining the separate signed-host and release gates.

## 2026-10-08 — Verify the integrated findings, image and canary checkpoint

- At `62859de`, all 3,244 parallel tests in 344 suites, six isolated timing tests in four suites, native integration executables, 148 contrast ratios and 648 adversarial cases pass. Repository/static and native app/extension compiler checks passed at `6ebe3b5`; the intervening commit changes only a test fixture and changelog.
- The new checkpoint includes collapsed findings, actual source-pixel/decode-work bounds and first-tranche surface canaries. Peak image memory, broader copy surfaces, remaining mode families, actual signed hosts and release prerequisites remain open; green native tests do not close them.

## 2026-10-08 — Retain copy-feedback coverage in an eligible mode

- The integrated 3,244-test run passed every new findings, image and canary test but exposed two stale assertions in the old Copy Concealed Text chip fixture, which invoked the action in Source. Move that fixture to Markdown’s Rendered mode, assert the action is offered, and retain exact clipboard, shared-chip and once-only announcement expectations.
- Repository checks and all native source compiler checks passed before this test-only migration. The complete test entrypoint is rerun on the committed fixture; no production behavior or copy policy is weakened.

## 2026-10-08 — Reconcile chrome regressions and the verified baseline

- Migrate old privacy-status assertions to the counted findings summary. Reading-order, notice ordering and narrow-pane fixtures now use a real reformatting notice, so their header and content-space assertions stay meaningful. All 28 focused chrome/zoom tests pass; no geometry or ordering assertion is removed.
- Record full hosted static/macOS success at `7e062b9`, and reconcile the plan’s notebook, hidden-content and copy rows with their actual implementation evidence. Record the newer findings and nine-mode canary batches without closing signed-host or release gates.

## 2026-10-08 — Bound actual image sources and unfinished decode work

- Own one six-family raster signature/type/suffix policy and a 40-megapixel source limit. Adapters and both drawing paths validate actual headers; declared and oriented dimensions must agree. Thumbnails keep their separate smaller pixel ceiling and now refuse raster families that adapters never produce.
- Admit at most two small native page decodes, or one source above 16 megapixels exclusively. FIFO tickets retain capacity until noncooperative native work actually returns, including cancellation, generation replacement and scheduler deallocation; queued/grant races resolve once. Stale results cannot reach a replacement page.
- Count actual bitmap row strides and component depth against the resident page budget, including overflow and post-decode rejection. Complete synthetic boundary PNGs, AVIF/HEIC images, orientation mismatches, padded 16-bit storage, held native calls and recognized-but-disallowed image families are covered.
- The combined 375-test/58-suite selection passes; a follow-up independently confirms that all four rejected thumbnail fixtures are valid ImageIO images. The source and concurrency caps do not establish the 100 MiB peak-footprint target; fresh Release-worker measurements and signed-host/minimum-OS observations remain open.

## 2026-10-08 — Inspect real concealment through nine native modes

- Add independent synthetic canaries for plain text, source code, JSON, JSON Lines, CSV and Markdown, including exact canonically equivalent UTF-16 spellings, escaped credentials and safe sentinels. Run real adapters through the privacy pipeline and require the expected nine-mode coverage.
- Inspect derived models, realized table/outline rows, attributed metadata, view and virtual accessibility trees, expanded finding details, announcements and every advertised private clipboard representation. Actual source replacement must clear stale values. Independent thumbnail services verify default withholding and the final drawing scene under synthetic-only test limits; source bytes and metadata remain unchanged.
- All first-tranche canary tests pass in the 375-test combined run. A missing first-responder setup was corrected before asserting native outline Command-C delivery. The remaining nine mode identities, broader adapter families and actual Finder/VoiceOver surfaces remain explicit work; no OCR or release-wide privacy claim is made.

## 2026-10-08 — Collapse findings into a bounded native disclosure

- Replace six always-visible finding rows with an initially collapsed, pluralized summary using the actual concealed-value count and copy policy. All bounded findings remain in a native scrolling disclosure capped at one quarter of the host safe-area height, with cloud-folder caution first and decoded detail limited visually to two lines while retaining its safe accessibility text.
- Copy Concealed Text is available only in Rendered and Invisibles. The summary replaces the duplicate privacy status line. New documents/loading clear disclosure; same-document mode and appearance changes retain it. User disclosure posts one layout announcement; programmatic transitions do not add duplicates.
- The combined 375-test, 58-suite run passes, including narrow/doubled-font geometry, scroll position, actual native disclosure action effects, private-board writes, source replacements and related image/privacy regressions. AppKit’s accessibility press return value was false despite delivering the action; the mounted-control test verifies state and callback delivery instead. Signed Finder/VoiceOver and translated real-host layout remain open.

## 2026-10-08 — Reproduce collapsed-findings and image-limit gaps

- Add native findings regressions for actual concealed counts, localized summaries, all bounded details, capped scrolling, large fonts, inert decoded detail, generation/mode persistence, copy gating and once-only disclosure announcements. API-only test seams preserve the old rendering until the next implementation commit; four fully covered draft localization keys support the new contract.
- Add complete compact PNG fixtures at and above 40 megapixels plus continuation-controlled noncooperative decoder tests. The existing behavior accepts the oversized source and frees cancelled decode slots before work returns.
- The 39-test combined behavioral RED reports 99 issues: 94 findings/notice assertions and five image-limit/scheduler assertions. No wall-time sleeps are introduced. The native renderer test target now directly depends on the real pipeline, formats, thumbnails and shared fixture support for end-to-end privacy tests. Retained log: `.build/quality-work/q50-q154-red2.log`.

## 2026-10-08 — Verify the combined native checkpoint and canonical ownership

- The combined checkpoint `5cfb8c1` passes repository checks, native source compilation, 3,200 parallel package tests, six isolated timing tests, every native integration executable, 148 contrast ratios and 648 adversarial cases. Logs are retained under `.build/quality-work/integrated-oct8-{check,compiler,test}2.log`.
- Static-tool self-tests caught temporary agent names added as new workstreams. Restore decision 027’s canonical workstreams and assign the new copy/notebook paths to their existing owners; preserve the exact workstream and per-stream localization assertions. Agent task names remain scheduling labels, not new repository workstreams.

## 2026-10-08 — Reconcile integrated plist and real-deadline checks

- The complete 3,201-test parallel run exposed an obsolete binary-plist scanner exclusion and a Mermaid real-deadline failure under competing CPU work. Assert converted binary plist scanning while preserving no invented encoding and concealed values; update its producer comment.
- The unchanged large Mermaid workload passes alone in 0.271 seconds. Move that existing probe to the isolated wall-clock pass with its original standard parser budget and ten-second assertion intact. The exact compiled-inventory guard now requires six serial tests in four suites. Six focused tests pass; full integrated verification follows.

## 2026-10-08 — Keep host evidence tests aligned with recorded observations

- Replace the obsolete assertion that every observation belongs to the retired identity with explicit historical/current artifact checks. The new assertion permits exactly the four recorded JSON Lines/notebook pane/panel claims, retains development-signing attribution, and still requires all thumbnails and macOS 15 observations to remain unclaimed.
- The full static entrypoint exposed the two stale assertions; all host-matrix tests pass after their migration. This changes validation expectations, not routing or product behavior.

## 2026-10-08 — Connect listing findings to Tag copy hygiene

- Recognize the typed hidden listing-name finding in the live copy gate. The shared sanitizer still removes only unsafe Tag spans; valid flags, other invisible characters and on-screen source remain exact.
- A two-format native clipboard regression first exposed eight semantic failures. Copy All and Source selection now pass alongside 69 related tests in nine suites, with private pasteboards and separate mode/copy announcements.

## 2026-10-08 — Report hidden archive and folder name characters

- Share contextual hidden-character classification across archive and folder names, retaining filename-direction warnings and exact displayed names. New typed risks count affected entries without carrying names or Tag payloads; folders remain metadata-only. Archive disguise comparison ignores formatting only in its comparison stem.
- Retain preview/count findings when annotation overhead exceeds a budget. Twelve new tests reproduce 19 semantic issues before repair and now pass; all 174 related regressions pass after migrating two obsolete archive-only assumptions. Real source/target bytes and unrelated schema labels remain unchanged.

## 2026-10-08 — Record signed baseline notebook routing

- Observe the small synthetic notebook in Finder's preview pane and Quick Look panel with concealed code and saved text output, attributed to the single registered signed 603e0d0 artifact. Update only these two matrix cells and the website projection; all 83 fixture-file hashes remain unchanged.
- Keep later notebook image changes, thumbnails and embedded keyboard focus unverified. The command probe reached Finder's search tab, which was closed after restoring the fixture folder; it does not establish preview shortcut behavior.

## 2026-10-08 — Preview realistic notebook figures with bounded source placeholders

- Register notebooks on the byte-input path with a 16 MiB/five-second family budget and strict encoding provenance. Replace image output values with inert JSON nulls, preserve exact surrounding text and remapped privacy ranges, and retain all non-image text/output/line limits.
- Preflight complete base64 and aggregate image budgets before allocations; admit only signature-matching saved PNG/JPEG figures and explain Source/Pages provenance. No cells or rich outputs execute.
- RED reproduced 20 semantic issues in 13 declarations; 129 integrated notebook/image-validator tests now pass, including privacy, cancellation, malformed/budget and source-integrity cases. Update decision 020's historical figure limitation; Finder and memory observations remain open.

## 2026-10-08 — Remove detected invisible Tag payloads from explicit copies

- Apply the approved copy-only policy to native text/multiple selections, structured rows and paths, Copy All and Copy Concealed Text. Keep valid flags, other characters, displayed storage and selection exact; remove content-bearing rich attributes only under the current finding gate. Tags-only selections replace old clipboard content with empty text.
- Confirm only successful writes with one chip and announcement. Private-pasteboard RED tests reproduced row, rich-link and empty-copy defects; all 18 new declarations, 101 related regressions and 43 feedback/command compatibility tests now pass. Decision 012 records the exception; signed Finder clipboard and spoken VoiceOver acceptance remain open.

## 2026-10-08 — Prepare copy, notebook and listing-name resources

- Add five typed messages for copy payload removal, notebook image provenance and hidden listing-name risks in all 14 development languages, including a CLDR count sentence. Regenerate plain/plural resources; 1,045 keys and six plurals pass reference/coverage validation. Translations remain drafts requiring native-speaker and installed-host review.
- Record disjoint specialist ownership for the active safety, copy and notebook work; the ownership audit finds no unowned files. Runtime implementations and their evidence are recorded in their own commits.

## 2026-10-08 — Attribute JSON Lines previews to the current signed build

- Remove only the stale duplicate SpacePane app registration and register the worktree's signed `603e0d0` artifact. PluginKit and process paths then identify one current preview provider; competing providers and extension preferences are unchanged.
- Observe fresh concealed JSON Lines in Finder's preview pane and Space-bar panel, including the Records control and typed mode accessibility label. Update only these two matrix cells; fixture hashes remain unchanged. Thumbnail, keyboard delivery and broader host gates remain open.

## 2026-10-08 — Extend hidden-character classification and marker parity

- Add interlinear annotation, musical and Egyptian formatting controls, out-of-context Mongolian selectors and contiguous Braille blank runs to the shared classifier and its byte prefilter. Keep isolated Braille spacing and expected Mongolian, emoji, Indic, flag and RTL contexts readable.
- Extend the independent exhaustive scalar oracle, real pipeline concealment/finding checks and exact Invisibles marker mapping. The 25-test selection first failed with 148 semantic issues, then passed; all 148 related regressions pass. No new finding kind or source-character mutation is introduced.

## 2026-10-08 — Record signed bundles and exact-commit hosted success

- Record successful signed Xcode build/launch at `603e0d0`, 33 language/fallback lookups across three bundles, artifact hashes and limited actual companion observations. The full hosted static/macOS run 37675384863 passes at the same commit.
- Finder shows concealed synthetic JSON, but two enabled same-identity development builds and two extension processes make artifact attribution ambiguous. Preserve that limitation; do not close Finder gates, change provider preferences or reset caches. Correct the retained Q150 log paths.

## 2026-10-08 — Scan hidden characters in decoded and converted documents

- Admit converted ebook/web text and encoded binary/random-access text to the shared post-concealment hidden-content scanner. Exclude generated summaries on every input path; preserve URL and geometry boundaries. Compressed text now reports its actual UTF-8 or BOM UTF-16 encoding.
- Centralize the bidi scalar predicate in HiddenCharacters and reuse it for archive filename risk, preserving direction-mark behavior independently of contextual prose exemptions.
- Eleven new tests first reproduced 13 issues in seven behaviors; all now pass. The related 208-test, 17-suite selection passes, including actual EPUB/FB2/MHTML/GZIP fixtures, displayed lines after concealment, filtered Tag detail, no-source-mutation, disabled-read checks and existing classifier/archive/decompression regressions. The remaining filename/folder classifier expansion and real-host acceptance stay open.

## 2026-10-07 — Link only current Swift compiler outputs

- Use each Swift target's output-file map as the integration object inventory, including whole-module entries and deduplication. Deleted-source and stale aggregate objects cannot be linked back into a host; missing current outputs fail explicitly. Legacy aggregate and Clang shim layouts remain supported.
- Four isolated inventory tests pass after reproducing stale/missing output failures. Without clearing the stale build cache, the complete entrypoint passes 3,125 parallel tests, five serial liveness tests, every companion/integration executable, 148 contrast ratios and 648 adversarial cases. All 21 static steps and 91 static-runner self-tests pass with no skips.

## 2026-10-07 — Conceal escaped source literals and bounded YAML flow values

- Inspect inert escaped source literals with the shared credential classifier, including JavaScript/TypeScript private fields, Java text blocks, literal-name call trivia and valid decoded prefixes of unterminated literals. Hash-comment rules follow the source language; Python raw literals stay inert. Preserve precise visible-URL handling and the existing conservative malformed-double-quote fallback.
- Add a request-bounded lexical YAML flow pass for local name/value bindings and scalar values, including arrays. It never resolves anchors/tags or evaluates content. Respect block/plain-scalar indentation and mapping-colon separation so prose brackets do not spend collection budgets. Existing node/depth/range/cancellation limits still apply.
- Twenty-three adapter grammar declarations pass, including review-driven RED/GREEN cases, raw/URL compatibility, malformed/alias fallback, exact source integrity and deterministic cancellation. All 3,125 parallel package tests plus five serial liveness tests pass. The full entrypoint then exposed an independent stale-object integration-link defect, repaired in a separate tooling change; host/surface-wide acceptance remains open.

## 2026-10-07 — Complete JSON grid facts and close thumbnail body fallbacks

- Collect JSON root-record counts and an exact decoded UTF-16 key union during the existing bounded scanner. Duplicate keys or more than 256 distinct columns discard the ambiguous schema, keeping only the record count; other scanner consumers do not enable this accounting. Formatted output retains facts and privacy annotations.
- JSON thumbnails use only concealed bounded headers and value-free column textures. Inferred plain-tab grids never assume their first record is a header, and a recognized grid that exceeds sample limits is withheld instead of falling back to body text.
- Inspect complete bounded markup lines before display clipping so a comment opener/closer beyond the visible prefix cannot expose a later comment body. Uncertain line/aggregate inspection limits decline the page. All 254 thumbnail tests, nine JSON-fact tests and related scanner/notebook regressions pass after semantic RED cases; source integrity and exact-key/count boundaries are covered.

## 2026-10-07 — Reflow Markdown paragraphs without changing safe source

- Join ordinary and same-depth quote paragraph soft breaks before inline parsing; keep explicit two-space/backslash hard breaks and structural block boundaries. Fences, notebook code cells, blank paragraphs, metadata, tables, lists, math, footnotes and Contents offsets retain their existing owners and bounds. Cancelled rendering returns no derived document.
- All twelve semantic reflow tests pass after their RED run. The broader 1,256-renderer-test run found only the intentional legacy soft-break expectation; after migrating that fixture, all 19 focused reflow/native-interaction tests pass. Exact safe code units, concealed selection/private copy, decorations, first-strong direction, limits and notebook delegation are covered; Finder reading review remains open.

## 2026-10-07 — Record a fingerprinted Release measurement baseline

- Both corrected Release workers completed on clean `acec21b`: 16 pipeline scenarios and 14 actual offscreen native-renderer scenarios, each with ten cold and fifty warm samples. Record exact source/build/fixture hashes, all stage and TASK_VM_INFO samples, unchanged-source checks and compressed raw reports in the validation artifacts.
- The 1 MiB source case measured 429.595 ms warm whole-path p95, 580.632 ms maximum and 311.902 ms changed-style p95. These identify optimization work; this branch baseline is not an interleaved A/B comparison, master baseline, Finder first paint or an oldest-OS result. No performance gate is closed by a descriptive report.

## 2026-10-07 — Publish accessible mode and state transitions once

- Label the native mode selector through the typed resource in all 14 language drafts. After a visible mode/state hierarchy is installed, post one payload-free layout-change notification; repeated selections, restyles, resizes and unrevealed loading grace remain quiet. Structural notifications remain independent of spoken feedback.
- All nine new semantic tests failed before implementation and pass afterward; all 1,244 renderer tests pass, including actual controls/chords/Contents navigation, delayed loading/cancellation, state recovery and resource lookup. These recorded AppKit notifications do not establish delivered VoiceOver behavior in Finder or speaker review.

## 2026-10-07 — Give Rendered prose a native reading layout

- Rendered Markdown, notebooks and converted documents now use the system text face at the configured size, 1.4 line height and a centered measure of about 70 average advances. Code spans/fences use the selected code face. Reading mode always wraps and hides the gutter and Go to Line; Source restores its existing typography and commands without a schema change.
- Four semantic regressions failed before implementation and pass after it, covering undecorated prose, code family, width changes, exact safe code units, selection, inert attributes and private-pasteboard copy. All 1,244 renderer tests in 127 suites pass with the accessibility tranche. This is offscreen AppKit evidence; Markdown soft-break reflow and real host reading/accessibility review remain separate.

## 2026-10-07 — Use the catalog identity in log benchmarks

- The full Release pipeline reached its final append case and exposed a second obsolete oracle: `.log` has its own stable catalog identity, rather than `.plainText`. Match the actual `.log` ID; retain the concealment and deterministic-result checks. A direct Release worker probe confirms a ready, concealed 18,563-byte presentation. The incomplete benchmark run remains excluded from acceptance evidence.

## 2026-10-07 — Validate the committed baseline and repair the Release oracle

- Commit `78b7c7c` passes the full local entrypoint (3,067 parallel tests plus five serial liveness tests, integrations, 148 contrast ratios and 648 adversarial cases) and full hosted static/macOS run 37665845758. All ten previous hosted privacy regressions are repaired.
- Both fingerprinted Release workers compile. Runtime measurement exposed an obsolete benchmark expectation: oversized plain text correctly returns a bounded leading-line preview, while the worker expected input rejection. A separate Release probe confirmed the 39,998-byte safe result. Update the oracle to require a bounded partial preview with the original byte count, and report typed worker failures without a top-level Swift trap. Full measurements will follow; initial partial timings are not acceptance evidence.

## 2026-10-07 — Draw value-free grid thumbnails from parser facts

- Carry typed parser counts through ParsedTextDocument and TextPresentation. Delimited data, SQLite, Arrow, Avro, supported NumPy arrays and Parquet use existing bounded reads; partial counts stay lower bounds, unsupported metadata declines a grid, and Arrow rejects invalid/overflowing row totals.
- Replace value-bearing table thumbnails with bounded headers, numeric/text/empty/unknown column textures and locale-formatted count symbols. No grid body values are stored or drawn. Preserve privacy withholding; omit technical schema headers, use honest partial column counts for plain-tab probes, and classify opaque cells as unknown.
- All 240 thumbnail and 887 format tests pass, including real data fixtures, four locales, integrity, bounds and semantic RED→GREEN count corrections. The final explicit-locale grid check passes nine tests; all renderer/core checks except the separate source-grammar RED and all native source compiler checks pass. JSON record producers and actual Finder thumbnail observations remain separate work.

## 2026-10-07 — Repair full-suite privacy compatibility regressions

- Full hosted run 37660118718 at `6412753` compiled but exposed ten integration failures. Restore plural credential protection while keeping bare/numbered structural keys and the exact reserved plural-format metadata readable. Parse the ordinary `proxy_pass` directive without treating its URI/query as a longer secret key; credentials inside its value remain protected.
- Preserve precise source-visible URL concealment when an unrelated escape is decoded. A bounded exact-UTF-16 multiset accounts for each visible URL; extra/escaped duplicates, other credential grammars and quota uncertainty still conceal the complete original value.
- All ten hosted regressions and ten new compatibility declarations pass in a full 3,074-test run. Its only failures are 14 intentional assertions exposing the separate source-grammar tranche. All 20 portable checks and every native source compiler check pass. This does not claim the entire uncommitted feature batch is green.

## 2026-10-07 — Verify Contents copies through a private clipboard

- Replace the old empty-return copy stub with a real named private pasteboard check. Verify selected safe headings, an empty selection preserving the clipboard, and exactly one successful-copy event.
- Add host integration coverage for the Contents selection, shared Copied chip, single announcement and injected timer expiry. Both checks pass in all 1,231 renderer tests; no test reads or writes the user's general clipboard. Update stale comments to reflect the adopted copy-reporting contracts.

## 2026-10-07 — Measure actual native renderer stages

- Add optional renderer observation at mode derivation, tokenization, logical-line indexing, text storage, styling and layout. Counts describe the actual work, cache hits emit nothing, and ordinary previews avoid measurement clocks and count traversals. The Release native worker supplies the observer.
- Six observer tests and all renderer suites pass: 1,231 tests in 125 suites. Tests compare nil/measured output, exact Unicode replacement, deferred source and actual TextKit work. Enabling a gutter on existing content exposes two real layout passes in both measured and ordinary hosts; the instrumentation retains both. Release worker execution and Finder first-paint measurements remain separate.

## 2026-10-07 — Preserve the 3D camera across compatible live reloads

- Retain the user's orbit, pan, zoom and up-axis when a replacement geometry presentation has the same format and full bounds. Replace GPU resources normally. Explicit new-file resets, changed or translated bounds, changed format and cleared sessions still restore the conventional view.
- Three semantic assertions reproduced the previous reset behavior; all 14 native geometry lifecycle/interaction/summary tests pass after the fix. Actual Finder live-reload observation remains a separate gate.

## 2026-10-07 — Finish the remaining renderer palette migrations

- Use the shared hairline and muted roles for image-page placeholders/captions and plot frames. Remove the two remaining chrome-ink allowlist entries; the static gate now permits no deferred renderer files.
- Existing image-page, plot and color-scheme contrast suites pass on the Mac. All 20 portable checks pass with no skips. This is source/AppKit evidence; signed-host appearance and accessibility remain separate acceptance gates.

## 2026-10-07 — Guard the serial liveness test inventory

- Select timing-sensitive tests by three named suites instead of five method substrings. Validate the built Swift test inventory and exact count before splitting parallel and serial passes; missing, added or duplicate selected tests fail explicitly. Test bodies are unchanged.
- All 91 static-tool self-tests pass; actual discovery selects five liveness tests, and those plus nine CAD XPC wait cases pass serially. Record the existing CAD synchronous-adapter/semaphore exception and its cancellation/worker boundaries in decision 027.

## 2026-10-07 — Conceal adapter-owned credential bindings and escaped values

- Recognize same-object JSON/JSON5, YAML block-item and XML element name/key-to-value bindings; conceal all matching duplicate values without crossing object/record boundaries. Inspect decoded escaped values with the shared recognizer while annotating original source bytes.
- Add metadata-selected `.netrc`/`.pgpass` parsing with bounded comments/escapes, concealed inert macros and conservative malformed handling. Recognize sensitive literal-name source calls and environment assignments; conceal the complete bounded expression, including concatenated/text-block/comment forms, without evaluation.
- Semantic RED exposed and then verified multiline/expression fixes. The 13 adapter test declarations cover 29 positive cases, 14 ordinary negatives, scope/duplicate/remapping checks, bounds/cancellation and isolated real-file bytes/mtime/permission integrity. They pass in the 1,308-test renderer/privacy/liveness tranche and all native source compiler checks. Remaining mainstream source-literal/call-trivia/YAML-flow cases are a separate tranche; no universal grammar coverage is claimed.

## 2026-10-07 — Extract the stable preview header and limits component

- Move notes, modes, provider badge, transient chip and limits controls plus their existing styling/collapse constraints into `PreviewHeaderView`. The facade retains commands, findings, content, resources and lifecycle; typed mode callbacks and forwarded named seams preserve behavior. Safe-area anchors still use the actual host, and the ignored container preserves the full accessibility child set.
- Focused header tests and all renderer suites pass, together with privacy/liveness coverage: 1,308 tests in 140 suites. Package/companion/preview/thumbnail/CAD-service compiler checks pass. This completes the four sequential Q-31 moves; visual changes and real Finder observations remain separate.

## 2026-10-07 — Retire the unused Xcode project generator

- Remove `script/generate_project.py` after a Mac inventory confirmed no build, CI, environment or tooling callers. Replace the stale signing error hint and document the checked-in project/shared scheme as the source of truth, as approved in D25d. Historical references remain attributable to the old state.
- Xcode lists all four targets and the shared scheme; the project validator passes its target/embedding/CAD/privacy/catalog/localization checks after removal. The checked-in project graph is unchanged.

## 2026-10-07 — Preserve AppKit accessibility cells in reading order

- Keep all platform accessibility elements when ordering preview chrome, including cell-backed labels and mode controls. Rank cells by their named owner/control view and retain stable order for unknown elements; the previous view-only cast silently discarded three controls.
- Strengthen the regression to require all seven semantic owners and preserve the raw system child set. The pre-fix semantic test failed; all focused chrome skeleton/state/command tests pass after the fix. This is package/AppKit evidence, with actual VoiceOver delivery still pending.

## 2026-10-07 — Finish benchmark provenance and reconcile implementation evidence

- Extend both Release workers with typed stage collection, actual physical-footprint probes and separate process-lifetime peaks; add bounded CSV/listing/Contents/findings/1 MiB/append fixtures. Fingerprint source, build context, executables and fixture bytes, and reject stale/mixed comparisons without changing schema 1. All 54 comparator and ten runner tests pass; strict worker typechecks pass. Stable Release and actual hosted measurements remain pending.
- Add runner self-tests to the portable gate (all 20 steps pass), spell test-only Void signals explicitly to avoid a tree-sitter tuple-call parser gap while preserving compiled behavior, and reconcile PLAN and the pending Mac queue with the full green S0 recovery and later focused/compiler checks, and retain unobserved host/release gates. Synchronize the original exact commit history to PR #12 through GitHub's API after receive-server errors, without force-pushing.

## 2026-10-07 — Show genuinely empty structured sources as empty

- Add registration-owned `EmptyInputPolicy`: text registrations default to an empty preview for a confirmed zero-byte file; binary formats keep parsing unless explicitly opted in. Property lists and strings dictionaries opt in. The common pipeline still performs type policy, bounded read, privacy and output validation; truncated/missing bytes and nonempty malformed documents do not become empty previews.
- Seven previously failing structured formats now use the existing localized empty state. Five focused tests cover 12 source suffixes, binary opt-in, malformed/missing-byte cases and disabled policy; related state/budget/stage tests and all native source compiler checks pass. This avoids per-parser empty-file exceptions and preserves every logical format identity.

## 2026-10-07 — Add opt-in pipeline stage observations

- Add a typed UI-free stage observer with monotonic intervals, bounded actual-work counts and optional fixed-name OSLog interval signposts. A nil observer does no clock/signpost work. Observe one pipeline-worker execution, including early policy/failure/cancellation exits, without counting executor queue wait as worker time.
- Seven tests first reproduced missing pipeline events, then passed for exact once-only execution, old-API forwarding, no added reads, early/cancelled outcomes and bounded interval values. Benchmark fixture, footprint and renderer-stage integration continues separately; these observations do not establish first visible Finder content.

## 2026-10-07 — Bound preview-host waits and reject late results

- Add package-tested `PreviewHostSession` around the shared Dispatch reply gate, with one request identity, one start and one terminal delivery. Cancellation stops pending work; the 30-second host ceiling installs the existing timed-out state even when work has not cooperated. Late results cannot replace it or complete a replacement request.
- Integrate the session into the Finder preview controller and preserve content-ready handler timing. Register live reload before invoking the completion callback so a reentrant replacement can stop it safely. No generic family budget is invented for the host timeout; D12's early/grace completion choice still awaits the signed-host experiment.
- Four session tests cover success, suspended noncooperative work, cancellation before I/O and replacement identity; existing reply-gate tests and all native source compiler checks pass. A test helper's noncopyable Mutex capture was corrected to retain its owning object.

## 2026-10-07 — Share one credential-value recognition policy

- Move the approved value grammars into UI-free `RecognizableSecretPolicy` for both the final privacy filter and decoded adapter strings. Cache immutable regular expressions; expose only typed ranges/findings, explicit match-limit overflow, and a first-match Boolean. Keep the independent slow oracle separate and retain exact concealment precedence/counts/fallback behavior.
- Eight API test declarations cover value/ordinary corpora, exact UTF-16 spans, overflow, early stop, deadline/cancellation and concurrent use. They pass alongside the Q16 and legacy privacy/concealment suites; decoded/sibling adapter behavior is the next separate increment.

## 2026-10-07 — Extract the native text content stack

- Move the stable TextKit 1 text/scroll/gutter stack, source/style caches, wrapping, measurement and reading-position restoration into `PreviewTextContentView`. Keep host resources, interactions, selected modes and outer layout in the facade; preserve its named lookup seams.
- Convert three existing geometry suites' comparisons into facade coordinates so they verify the same displayed rectangles through the new wrapper. Characterization proves unchanged safe text does not replace the text stack or edit characters, and canonical-equivalent replacements retain their exact spelling.
- All 76 focused native layout/appearance/source/gutter/interaction/chrome tests in ten suites and package/app/preview/thumbnail/CAD-service source compiler checks pass after the extraction. Header extraction remains a separate next step.

## 2026-10-07 — Share the bounded request reply timer

- Move the existing Dispatch timer and once-only reply gate into PreviewCore as `RequestReplyGate`, retaining the thumbnail API names as compatibility aliases. This gives preview-host timeouts the same tested primitive without a renderer or thumbnail dependency. All 12 existing timer/reply/service tests pass after the behavior-preserving move.

## 2026-10-07 — Improve credential recognition and exact source invalidation

- Replace substring-only field classification with bounded separator/camel/acronym tokens, explicit credential aliases and ordinary/public-key exceptions. Add provider/private-key value grammars using the existing finding kind; validate prose Basic/Bearer shapes so ordinary phrases remain readable. Bound examined key scalars as well as visible scalars/tokens and decode only bounded credential prefixes.
- Establish a synthetic recall corpus: 228 positive samples across 57 families and 120 ordinary lines. Baseline concealed 68 positives and falsely concealed 15 ordinary lines; the new rules conceal all 228 and leave all 120 unchanged, including every family individually. These are corpus results, not a universal recognition guarantee. Structured sibling/escaped-value and credential-file grammars remain the next increment.
- Preserve an independently implemented slow concealment oracle with explicitly documented policy changes. The new 13-test corpus suite and selected legacy privacy/concealment suites pass, including node/output/cancellation/deadline contracts and public-key negative cases.
- Make `TextPresentation` equality compare exact safe UTF-16 code units as well as metadata, so canonical-equivalent replacements invalidate the SwiftUI bridge and derived views. The regression first failed at presentation/outcome/result equality, then passed with existing native Unicode replacement checks; byte-identical content remains equal.

## 2026-10-07 — Add typed privacy-safe host diagnostics

- Add debug-level request start/settings/end events to both Quick Look extensions, with typed outcomes, elapsed time and bounded point dimensions. Events accept no filenames, paths, content, parser errors or arbitrary messages. A request ends at most once across completion/cancellation; thumbnail timeout/cancel events do not invent a settings-load state.
- Extend `--logs`/`--telemetry` to include debug events from the app's exact subsystem and extension subsystem prefix. Four lifecycle/concurrency/geometry/privacy-contract tests and the package/native source compiler gates pass. Real-host delivery remains to be observed.
- Register the four renderer extraction boundaries in the ownership table, preserving disjoint state/mode/text/header integration grants.

## 2026-10-07 — Extract the preview mode policy without changing defaults

- Move typed titles, available-mode ordering and initial-mode precedence into `PreviewModePolicy`; keep capability/model derivation in `SafePreviewModes` and retain its forwarding API. Policy inspection does not evaluate the lazy Profile model.
- Pin all 18 mode titles, complete ordering, cross-family precedence/fallbacks and Profile laziness before moving the implementation. After extraction, 136 related mode/chrome/document tests in 14 suites and package/app/extension/CAD-service source checks pass. Structured-first/default-first behavior remains a subsequent, separately validated change.

## 2026-10-07 — Repair reproducible CAD builds and share verification tools

- Repair the clean pinned OCCT build by exposing only `DE_ShapeFixParameters.hxx` through the existing TKXSBase toolkit. Preserve the source/archive bytes, 16-toolkit link closure and dependency revision; no DE implementation or new runtime library is added. Six new manifest tests and 52 source-offer tests pass; the arm64 kernel/helper build and all 13 synthetic worker tests pass. Update the [dependency audit](docs/dependencies/occt.md).
- Add the portable Release benchmark comparison tool with 41 tests: ordered interleaved runs, paired-cluster bootstrap intervals, independent p95 guard, strict metadata/raw-summary validation and explicit insufficient/inconclusive outcomes. It distinguishes core, offscreen native and real-host evidence; RSS is never reported as physical footprint.
- Add the nonshipping `PreviewTestSupport` target for shared byte-identical Data/draw.io fixtures and one bounded, cancellation-aware recording byte source. Preserve test-facing aliases and change the generator's canonical destination. Related Data/draw.io/recording/mode checks pass: 207 tests in 34 suites. Broader shared builders/temporary fixtures remain separate work.
- Add both new tool self-tests to the existing CI static gate (19 passing steps, no skips). Isolate the missing-parser self-test from the documented `.venv-tools` fallback so local development dependencies cannot change its expected outcome.

## 2026-10-07 — Preserve effective request limits and extract state presentation

- Add the UI-free `PreviewResult` contract, retaining the outcome-only pipeline API. Carry the selected family/override budget through the companion, appearance samples, Finder preview and live reload. Disabled/invalid/unclassified requests never invent a limit. The renderer now uses the existing localized limit variants for all seven applicable failure types.
- Extract state/notice composition into `PreviewStatePresenter` while keeping loading, announcement delivery and view lifetime in the facade. Strengthen the named-view identity checks to permit internal composition without losing attached content or TextKit identity.
- Validate seven pipeline budget checks, 97 focused renderer tests in eight suites, package and all native source typechecks, and every companion-model executable including six live-reload checks. The new real-file reload case preserves limits through failure/recovery and clears them on disable/cancel. No additional source read or persisted schema change is introduced.
- S0's exact commit `a063847` also passed the complete hosted macOS and static jobs in [run 37648392943](https://github.com/canburaks/prev/actions/runs/37648392943). Real signed-host observations remain separate.

## 2026-10-07 — Recover the native quality-program baseline

- Replace the thumbnail cancellation test's arbitrary sleep and elapsed-time assertion with a gated noncooperative reader. Prove that cancellation replies before the reader returns, then verify admission cleanup and rejection of late bytes. Production cancellation behavior and independent timeout tests are unchanged.
- Run the focused native thumbnail/reply/admission suites (39 tests), repository checks including the pinned Swift syntax parser, and package/host typechecks successfully. Recover all three missing companion integration checks and pass the full test entrypoint: 2,946 parallel package tests, five serial liveness tests, every integration executable, 148 contrast ratios, five appearance groups and 648 adversarial cases. Local S0 recovery is complete; hosted verification and real-host observations remain separate. Track the disjoint implementation grants and subsequent results in [the implementation record](docs/validation/quality-program-implementation-2026-10-07.md).

## 2026-10-07 — Synchronize the quality-program PR and plan its remaining implementation

- Fast-forward the named local branch from the research-only `4a1580c` to the PR's `f391354`, then merge `master` (`3339304`) while preserving the quality program, Fluid Functionalism interactions and both date fixes. Retain both changelog histories and synchronize the npm lockfile with the combined dependencies; the pnpm lock already contained them.
- Reconcile PLAN and decisions 026/027 with committed source, add the complete [continuation plan](docs/plans/2026-10-07-quality-program-continuation.md), and append five identified Round 3 commits to the pending Mac queue. Recorded owner answers remain in force; no implementation wave or host gate is marked complete.
- Recover the actual validation boundary: run 33 was fully green; run 40 compiled and ran 2,946 package tests with one cancellation-timing failure; head run 41 skipped the macOS job. Three referenced companion integration files are absent from the committed tree and must be recovered before those checks can run. No Swift behavior is changed by this synchronization.
- Verified on this Mac: portable static gate (16 passed, Swift syntax skipped for unavailable tree-sitter), reproducible npm install, website checks/build and 42 production Chromium hydration loads across all 14 languages. Header visual comparison remains different at 1.50%/0.57%, matching the existing recorded reference drift. Two existing vendored lint warnings remain. See [the dated validation record](docs/validation/quality-program-sync-2026-10-07.md) for commands, limitations and native recovery blockers.

## 2026-10-07 — Round 2 hosted run: the companion contrast fix (implementation, authored without a compiler)

- **Companion contrast (Round 2 fix, authored without a compiler; verification pending).** The hosted run's only failure, `CompanionContrastChecks` at 1.18:1 for the hint ink on the dark page, was a colour made under the light appearance: `CompanionInk.hintColor` is now a dynamic `NSColor(name:dynamicProvider:)` (first use in the repository, behind `CompanionInk.hintInk(for:)`, which picks white under the two dark appearances and black otherwise at the same 0.62 alpha; the worst calculated ratio is 5.6:1 on the dark badge fill). The check makes the ink under each appearance and under none, draws it under each, requires the chosen ink, adds the window and badge fills, prints every ratio with its RGBA and lists all failures before exiting 1.
- **Hosted run 33 (2026-10-07, commit 8ce6ec7, dispatched by hand in full mode): green.** The package builds, the app and both extensions type-check, every package test and integration check passes, and the contrast check measures 148 ratios in the four appearances at 4.5:1 or better (the printed ratios are in the queue row). This closes the Round 2 cloud work; what remains for Round 2 is observation on a Mac (the queue). The ownership table now carries the Round 3 workstreams `ux-tables` and `ux-setup` and the round's file grants.
- **Catalog `primaryView` (Q-32, owner decision D1; authored without a compiler; verification pending).** Every catalog format names the view it opens in (`PrimaryView`: source, outline, records, rendered, summary, table, rows, plot, files, pages, diagram, geometry), with the values the renderer's policy chooses today (JSON and JSON Lines still open in Source until D1 is implemented after the Wave 1 measurement); hosted run 35 then corrected six values from the samples (Avro, Arrow and NumPy open in Table, Parquet in Rows; GZIP and XZ open in Source because their samples carry text, a compressed TAR opens in Files) and the drift test now previews each sample's named root, so the app bundle is classified as a bundle. `FormatDescriptor.primaryView` is decoded from the JSON and defaults to `source` for in-code descriptors. `CatalogPrimaryViewTests` pins the shape; `CatalogPrimaryViewDriftTests` runs every built-in appearance sample through the pipeline and the mode policy and fails on any format whose catalog value differs from the mode it opens in, or whose sample does not reach the policy. The field is intended for the companion's renderer pill (Q-101) and Try Preview card (Q-97); those consumers remain to be implemented (status corrected on 2026-10-07).
- **Documentation hygiene (Q-25, remainder).** PLAN gains a milestone status matrix (implemented, package-tested, compiled, observed, with the evidence records); the progress sections stay in PLAN because they hold open boxes, which the plan must keep (a recorded exception to Q-25's "moved to validation records"). The undated validation files already carry a date line, so their names are kept to preserve links. README's localization section now describes the plural tooling and the additions files.

## 2026-10-06 — Round 2 of the quality program: the Wave 2 foundations (implementation, authored without a compiler; hosted compile pending)

Ten parallel agents with disjoint file ownership wrote decision 027's group B foundations and a few Wave 3 items that need no observation; the lead integrated, applied the strings, retired unreferenced keys and ran the gates (static gate 10 steps, gate self-tests, tree-sitter syntax over 675 Swift files, ownership audit with no unowned file, localization validation at 1,040 keys with 5 plural keys). Nothing here was compiled before the push; the macOS job compiles and tests it next, and the queue carries one row per workstream.

- **Chrome (Q-33, Q-35, Q-37, Q-46, Q-30 seams, typed notices).** `PreviewChrome` owns the chrome metrics (inset, gap, row gap, accessory and MIDI strip heights, chip slot, spinner delay, chip duration, a `compactWidth` placeholder with 24 pt hysteresis) and the literals in the chrome files use it. `NativePreviewView` gains header and content layout guides, safe-area pinning, a constant mode-control position with notes below it, a bottom limits slot, a chip slot, density decided in `display` and `layout()` before the document size, `forcedDensity` for the Theme sample, `accessibilityChildrenInNavigationOrder`, the Option-Command 1…9 mode chords with focus hand-off, the context menu built from the command table, and the internal seams `displayedStatus`, `displayedModes`, `selectedMode` and `contentView(for:)`. `NativeStateView` and `NativeStateContent` show loading (after the spinner delay, cancelled when content arrives first, with an injected scheduler), empty (a 0-byte ready presentation), unavailable, disabled, settings unavailable and configuration unavailable as one accessibility element with words from `PreviewFailureCopy`; `NativePreviewPane` accepts an outcome and a loading flag with the old entry point forwarding. `PresentationNotice` types notices as limit, fallback or provenance (`lines` stays as a shim) and limits go to the bottom slot. One `PreviewCopyReporting` callback feeds one Copied chip (no motion under Reduce Motion, one announcement, cancelled by a new generation); zoom is a chip. 73 new tests in six Chrome files.
- **Test seams (Q-30).** `descendants(of:in:)` in `ViewLookupSupport.swift` and 82 of 86 direct-subview lookups in 26 renderer test files moved onto the seams, existing members or the helper; two private walkers deleted; no assertion changed.
- **Palette tiers and the announcer (Q-34, Q-36).** `muted` and `hairline` in all 14 schemes (muted is the comment colour, AA everywhere, 7:1 in High Contrast; hairline 1.40–1.44:1, 3.2:1 in High Contrast), `NativeTextPalette.muted`, `.hairline` and `.mutedUsesSizeCue` (true for exactly Solarized Light, Solarized Dark and One Dark, per owner decision D11), 15 contrast tests. `PreviewAnnouncer` with its policy (states, mode switches, copies, filter and sort results, zoom, 3D presets; never content, never live reload), a recorder for tests, and spoken-string tests in every language. The chrome, modes, 3D, MIDI and tree views announce through it and draw muted text and hairlines from the palette; a new static-gate step refuses system secondary ink or alpha in the renderers outside two files the next round migrates.
- **Concealment and the worker (Q-43, Q-40).** `DefaultPrivacyFilter` builds the safe text in one forward, cancellable pass over UTF-16 and returns a native string; its own matches are capped by `maxJSONNodes`, and over the cap the whole text is concealed with one finding (the adapters' answer for their own ranges; a decision the lead accepted as the safe default). Byte-identical oracle tests over the corpus and adversarial shapes. `PreviewWorkerExecutor` (a `DispatchSerialQueue`, first use in the repository) is the worker actor's executor, injected through `PreviewPipeline.init(executor:)` with a per-pipeline default; a `dense-secrets` benchmark case. Thumbnails: `ThumbnailAdmission` (about half the cores, cancellable FIFO waiters), a once-only `ThumbnailReplyGate` on a Dispatch timer, `ThumbnailBadge` from the catalog suffix on every reply (first use of `extensionBadge`), hidden-character and comment rules for drawn runs, notebooks draw cells (owner decision), probe flags; decision 022 amended.
- **Platform (Q-44, Q-27, Q-45).** `CADPeerRequirement` accepts the Mac App Store certificate marker or the team OU; the service uses it. The CAD client waits on a `DispatchSemaphore` with a 25 ms cancellation slice instead of sleeping. `script/check_release_archive.py` rewritten (exact entitlement sets per role, one App Group array, hardened runtime, identifiers, `$(`-free nested plists, CAD peer values, privacy manifests) with 73 Python tests now in the static gate and CI; privacy manifests for the app, both extensions and the CAD service in synchronized folders; `validate_project.py` checks them; the release checklist records the checks and the TestFlight caveat.
- **Modes and keys (Q-38, Q-75).** `PreviewCommand`, a 25-command table matched by key code so AZERTY and Cyrillic layouts work, drives `PreviewShortcut`, the context menu and the Option-Command chords; Space no longer acts in Contents and Pages, arrows act only when the content view has focus, zoom routes to the visible mode view through `SafeModeZoomable`, and "Find is not available here" is announced; the table, outline and Contents views adopt the announcer and the copy report. 38 tests; two existing tests changed because Space no longer acts.
- **Copy (Q-110).** `PreviewFailureCopy` with a title and body for all 20 failures and the non-failure states, limit variants where a value applies, 51 keys in 14 languages; `settings.extensionConfigurationUnavailable` and `settings.extensionUnavailable` reworded without developer words; three long notices shortened; English and French straight apostrophes swept (Hausa and Turkish left for a native reviewer).
- **3D (Q-11, Q-80).** Unit provenance from every mesh parser (STL, OBJ and PLY undeclared; 3MF declared or assumed; IGES from the header or the worker; STEP assumed), localized unit symbols with "unit not declared" and "100,000+" wording (first use of `MeasurementFormatter` and the `UnitLength` family, wrapped), `geometryTooComplex` past `GeometryLimits`, a mid-tone material from the background with ambient 0.45 and a view-space light (lit spread at least 34 L*, darkest face at least 1.80:1 across the schemes), the up axis per format (Z for STL and 3MF) with a per-view Up Axis control never persisted, 65 tests including a Metal pixel check that skips without a device.
- **Companion (Q-91, Q-95, Q-96, Q-98, neutral status).** Undo for the eight overwriting actions through `CompanionSettings.perform` with the window's `UndoManager`, restoring only the replaced slice, an inline Undo row announced to VoiceOver; `CompanionTypography`, `CompanionInk` (hint ink at 5.8:1 or better, no accent text, no caption); Theme controls cleaned up (one label per control, a numeric field beside the size stepper, points in locale digits, fixed-width families first, Save explained when dimmed, the current profile marked, caution transfer notices); the standard "Settings…" item selects General and "SpacePane Help" selects About (decision 010 amended per D23a); the page name in the window title and the last page restored from the companion's defaults; a neutral one-sentence status; 35 keys in 14 languages; two new check files compiled by the model-check script. Six unreferenced keys retired.
- **Run 31 (after the fixes):** the package, the app and both extensions compile; all 2,942 package tests in 291 suites pass, as do the thumbnail suite and the undo, presentation, settings, model, file-drop, live-reload and SQLite checks; the new `CompanionContrastChecks` is the one open step (its dark-appearance resolution reports 1.18:1 for the hint ink, a check defect under repair).
- **First hosted runs of Round 2.** The package, the app and both extensions compiled after three one-line fixes (a non-optional `extensionBadge`, a typed `[UInt32]` literal, AppKit's layout guide `frame`), and 2,938 tests in 291 suites ran with 19 issues, all in Round 2 tests or layout: two cross-thread CAD wait tests and an existing CAD transport test starved the runner's three-thread pool with blocking waits (now waiting on a detached thread, serialized, with the cancellation half driven by the checkpoint observer); the concealment findings test compared Characters, so a combining mark after the token hid it (scalars now); the executor tests' 2-second request deadlines expired behind the same pool stall (rewritten with `NSCondition` gates, 30-second budgets and no pool-dependent assertions; one additive `package init(queue:)`); the pages view, an `NSScrollView`, never became first responder, so its document container now takes focus through a `keyboardFocusTarget` seam on `SafeModeContentView` that the focus hand-off uses; and the chip's required 104 pt slot squeezed the notes in a 200 pt pane until the text view had no height (the slot is now a preference with a floor for the notes). The workflow's failing steps end with an error digest because the log reader returns only a tail. Decision 020's keyboard paragraph no longer lists Space.
- **Lead.** The ownership table gained `ux-seams` and the files the round reassigned; the static gate gained the release-archive tests and the chrome-ink step; decision 010 and 022 carry their amendments; the three stale pins in the localization tests were dropped. Not verified: everything above until the macOS job reports; first-use APIs are listed in the queue rows.

## 2026-10-06 — First hosted compile of Wave 0 and the Round 2 contract additions (cloud; macOS job as the compiler)

- The macOS job ran on the Wave 0 commit: the repository checks (project, manifests, localization with the real `plutil`, icon) passed on the runner, and the package build stopped on one cause, thirteen errors deep: `SummaryWriter`'s synthesized memberwise initializer is private because of its private counters, and the runner's Swift rejects its use from the five adapter files that construct it, which the owner's toolchain had accepted. `SummaryWriter` now declares `init(context:)`. A scan of every struct with private stored properties found no other cross-file memberwise construction. Not yet verified: the rest of the build and the tests; the job runs again on this commit.
- Fifth hosted run (workflow run 19 on commit `faed33e`): every step green on the runner, repository checks, package build, app and extension type-check, 2,577 package tests, the thumbnail integration suite and the companion model checks. This is the compile-and-test half of Wave 0's exit; Finder observation, the companion in use and the plural resources at runtime remain Mac work in the queue.
- Third and fourth hosted runs: all 2,577 package tests and the thumbnail integration suite pass on the runner. Two more test-design defects surfaced only there: a shared `static let` `RequestContext` in the mesh and package test supports dated its deadline from the start of the run, so tests late in a 50-second parallel run saw `deadlineExceeded` (now built per use); the missing-service XPC test allowed 500 ms, which a loaded runner exceeds (now 5 s, its subject being the typed failure). The companion model check then died because the runner resolves `org.jupyter.ipynb` to another app's declaration that does not conform to `public.json`; the check now requires the formats that declare `public.json` and adds the notebook only where its type conforms on the host. The runs show the queue's first row is partly consumed: compilation, type-checking and the package tests are now verified by the job on every tagged push; Finder observation, the companion in use and the plural resources at runtime remain for a Mac.
- First full hosted test run (Xcode 26.6 on `macos-26`): 2,577 tests in 249 suites, 3 issues, all explained. `org.bittorrent.torrent` is not a system type: it resolved on the owner's Mac only because a third-party app declares it, so the runner's catalog test and `PackagePipelineTests` failed; the catalog now declares it as an imported type (conforming to `public.data`) and the three manifests gained the declaration (`sync_manifests.py`); decision 017's table is corrected. `PluralStringsTests` assumed Bengali digits for `bn_BD`; Foundation follows CLDR's Latin default, so the test now expects whatever digits the locale formats and no format directive. The run's duration was 47 seconds of tests after a 50-second build.
- The first hosted test run died at catalog load: `FormatCatalog.standard` called `preconditionFailure` when a system content-type identifier was not declared on the runner's macOS, which would also crash a preview process on such a host. The catalog now keeps the format with a dynamic stand-in type and records the identifier in `FormatCatalog.unresolvedContentTypes`; `CatalogContentTypeResolutionTests` asserts the record is empty and names the identifiers when it is not, so the next run says which type the runner lacks. The workflow's concurrency is now per job: a newer push cancels only a stale static run; a running macOS job always finishes.
- Two more differences between the runner's Swift and the owner's toolchain, both in lines that predate this program: a local `let text` whose initializer's closure called the method `text(for:item:)` (now `joined`, `NativeOutlinePreviewView`), and three test expectations on the removed `PreviewImage.label`. After these, the macOS job compiles the package and type-checks the app and both extensions; the test build is the next gate.
- Website (Q-180, the two requests the website workstream could not make without TypeScript): the demo's "Preview by" footer line is now a 16 px info symbol at the trailing edge of the panel header whose tooltip and accessible label read "Read-only preview · Preview by SpacePane" in 14 locales (`panel.readOnly` added, `panel.providedBy` back to the bare label); hero tiles whose spec says `isDefaultEnabled: false` carry an "Off by default" line, set on the STEP tile; `web/DESIGN.md` records both. Verified here with `npm run check` (data, locales, typecheck, lint) and a production build served to a headless Chromium: the symbol, its title and the badge render. The pixel comparison against the static site could not be used: in development mode the Finder pane's date ("Tuesday 19 May 2026" from Node, "Tuesday, 19 May 2026" from Chromium) trips a hydration error whose overlay covers the captures; a pre-existing issue, noted for the website workstream.
- Lead contract additions for Round 2 (decision 027, Q-32 and Q-11, additive with defaults): `PreviewFailure.unsupportedVariant` and `.geometryTooComplex` with the two exhaustive switches updated and localized messages in 14 languages; `GeometryLengthUnit` and `GeometryUnitProvenance` with `GeometryMeasurements.unitProvenance` (default `.undeclared`); `PresentationFacts` in the contracts module (value-free facts with regular and compact counts; no provider or strip yet); `ContractFactsTests`. Authored without a compiler; queued.

## 2026-10-06 — Wave 0 of the quality program: verification floor and the six Blockers (implementation, authored without a compiler; verification pending)

Everything below was written in a Linux cloud session with no Swift toolchain, by eight parallel implementation agents with disjoint file ownership and a lead that integrated, retired keys and ran the gates. The static gate (`script/check_static.py`), the tree-sitter syntax gate over all 614 Swift files, the ownership audit and the localization tools pass; nothing was compiled, run, rendered or observed in Finder. Every Swift change here is unverified until the macOS job or a Mac session runs the commands in [the pending queue](docs/validation/pending-mac-verification.md). No PLAN box is checked.

- **Verification floor (decision 027, Q-18 to Q-21, Q-23; amendment 2).** `script/check_static.py` and `./script/build_and_run.sh --check-static` run nine portable steps (manifests, appearance samples, localization tests and validation, shell syntax, decision-number uniqueness, wall-clock test names, the ownership tool, the Swift syntax gate), one line each; `--check` runs them first. `tools/check_swift_syntax.py` parses every changed or all Swift files with tree-sitter against `tools/swift-syntax-baseline.json` (three known parser gaps, counts recorded for tree-sitter 0.26.0 and tree-sitter-swift 0.7.4) and skips with a notice when the parser is absent (`--require` fails instead). `tools/ownership.json` and `tools/check_ownership.py --workstream --base` implement amendment 1's file ownership for the lead and twelve workstreams; every file in the tree is now owned (overlaps are deliberate and listed by `--audit`). `script/test_check_static.py` holds 92 tests for the gate. `.github/workflows/package.yml` adds a Linux `static` job on every push and pull request and a macOS `package` job (newest Xcode on `macos-26`, running `--check`, `--check-compiler` and `--test`) that runs on manual dispatch or when a commit message contains `[ci-mac]`, because the repository is private and macOS minutes are billed at ten times the Linux rate. `AGENTS.md` carries the "Working without a compiler" rules. The validator's `plutil` fallback is a strict `.strings` reader plus `plistlib`.
- **Plural tooling (Q-23, owner decision D8).** `tools/validate_localization.py`, `merge_localizations.py`, `generate_localization.py` and `add_localizations.py` accept a CLDR plural object per language for a plural key, check categories per language and placeholder parity for every key, write `<lang>.lproj/Localizable.stringsdict` (the `.strings` entry holds `%#@count@`), and lint unreferenced keys (an error, with `tools/localization/unreferenced-allowlist.json`), values identical to English outside `tools/localization/technical-names.json`, straight apostrophes and over-long header and notice strings (warnings). `PreviewStrings.count(_:_:locale:)` selects the category from the integer and prints the locale-formatted number as the second argument; `preview.count.lines` is the first plural key, with `PluralStringsTests`. The catalog and the thirteen translation inputs were sorted once by key (a large mechanical diff; every entry was checked equal). Additions files under `tools/localization/additions/` are the way workstreams add keys; the lead applies them and adds the typed cases below the `// [quality-program]` marker. Whether Foundation selects the category from the first argument, whether the `.strings` entry shadows the stringsdict and whether SwiftPM copies the stringsdict are Mac questions in the queue.
- **Text origin contract (Q-32 part).** `TextOrigin` (`source`, `reformatted`, `converted`, `summary`) on `ParsedTextDocument` and `TextPresentation` (default `.source`); `SummaryWriter` marks summaries, the JSON reformatter marks reformatted text, the property-list, draw.io, EPUB, FictionBook and web-archive adapters mark converted text, and the package, comic and MIDI adapters carry the writer's origin through.
- **Q-01, URL credentials (Blocker).** `DefaultPrivacyFilter` conceals the user information of `scheme://user:password@host` for every text format in one shared value pattern (a capture group, required literal `://`, source `.sensitiveField`, counted in `redactionCount`); the three adapter-local scans in the source, log and INI adapters are removed; the reference oracle gained the same pass. The pattern was compiled and exercised in the container's ICU 74 engine against 200,000 random documents and a model of the old scanner. Thumbnails of files holding URL credentials are therefore withheld by the existing concealed-content rule. Decision 019 is amended.
- **Q-02, image page labels (Blocker).** `PreviewImage` no longer carries an adapter-chosen label (a member path never passed concealment); the comic and iOS adapters stop filling it, the page view no longer sets a tooltip from it, and the pages are named only by the localized "Page n of m". `ImagePageLabelTests` guards the contract's stored properties and the exposed text.
- **Q-03 to Q-05, Q-13, structured views (Blocker and P0).** Table notices say what is true per origin (`SafeTable.Origin`: a data summary, a partial read, or a complete text source) and never claim Source is complete; YAML compact sequences attach to their key or the outline returns nil instead of re-rooting; the data-profile spoken description is indexed through the sort order; package, certificate, disk-image and torrent summaries open on Summary with Files one click away (decision 017, owner decision D17a; decision 014 carries the exception). Five unreferenced keys were retired (`fileTypes.header.state`, `fileTypes.partiallyEnabled`, `format.enabled`, `format.disabled`, `preview.table.truncated`).
- **Q-06, companion copy (Blocker).** The File Types subtitle, group state word, setup banner, size hint and About copy no longer imply Finder routing; the subtitle names the app and says macOS decides which app previews each file; `setup.notConfigured` names the extensions as the actor.
- **Q-07, Q-08, Q-14, documents (Blocker and P0).** Rendered EPUB, FictionBook and web-archive metadata use localized labels from `DocumentFrontMatterField` instead of English adapter labels and flags; images in converted Markdown become `![description]()` with one dimmed localized "Image:" marker; omitted images and linked files are counted (`OmittedResources`) and the offline notice appears only in Rendered and only when something was left out; the citation caveat and an English-terms note are one line in Rendered and References (owner decision D18, recorded in decision 015). `SafePreviewModes` renders from the presentation so a plain Markdown file's front matter stays verbatim.
- **Q-09, Q-180, website.** Support, home and demo copy describe the info symbol instead of a status line; the OS requirement names Apple silicon; routing sentences carry "when macOS uses SpacePane for the type" in fourteen locales and in the static pages; the hero leads with a default-on format and the STEP tour step says it is off by default; the privacy lede says "likely secrets"; the static privacy page date matches the Next.js one. The two TSX requests (an info-symbol button in the demo bar, an "Off by default" tile badge) are queued for the website workstream.
- **Q-10, Q-12, thumbnails (Blocker and P0).** The thumbnail service declines summary-origin text (`ThumbnailFallbackReason.summaryText`) instead of drawing a JSON summary page, and withholds secret-shaped files by name and shape (`ThumbnailSecretShape`, `ThumbnailLimits.withholdsSecretShapes`, default on); 7-Zip folder and pack-stream counts are bounded by `maxEntries` and digest vectors are read without allocating; the CAD loggers use the bundle identifier as subsystem; `script/build_cad_worker.py` extracts the OCCT archive into a fresh directory with a data filter and a marker (the first Mac run re-extracts and rebuilds the kernel once). Decision 022 carries the pending amendment for shape-only thumbnails.
- **Records.** `docs/decisions/README.md` indexes the records; decisions 014, 015, 017, 019, 020, 022 and 026 carry dated notes; the 29 owner questions are answered in `docs/reviews/2026-10-06-quality-review/owner-questions.md`; decision 027 lists the Wave 0 progress.
- Not verified: compilation, tests, Finder behaviour, the plural resources at runtime, translation quality. The pending queue holds one row per concern with the exact commands.

## 2026-10-06 — Ten-dimension quality review and the best-in-class quality program (review and planning)

- Documentation only; no product code, project configuration, resource or string changed. The review ran in a Linux container from source only: nothing was compiled, run, rendered, measured or observed in Finder, and every runtime statement in the reports is labelled as inferred or as quoted from the repository's validation records.
- Ten parallel reviews under `docs/reviews/2026-10-06-quality-review/`, one per dimension against one brief, one severity scale and one report template: preview chrome and non-content states (score 2), structured views and modes (3), documents, media and 3D (2.5), the companion (3), performance (3), security, privacy and safety (3.5), accessibility and localization (3), architecture, code quality and verification (3), platform integration and release (2), and thumbnails (2). Each verifies the self-audit's claims and decision 026's assumptions for its area with `file:line` evidence, ranks recommendations by impact and effort with a "doable without a Mac" verdict, and ends with a static check list and an ordered Mac checklist.
- `docs/reviews/2026-10-06-quality-review/README.md` synthesizes them: the scorecard, twelve cross-dimension findings, six Blockers (URL credentials concealed only by three adapters and drawn into thumbnails; comic page labels bypassing the privacy filter; a table notice that claims Source is complete when it is not; a File Types subtitle that promises Finder routing; rendered ebooks printing English adapter labels; citations with English-only terms), corrections to the self-audit, decision 026 and four other records, and the ranked opportunities.
- `docs/decisions/027-best-in-class-quality-program.md` (status: proposed) is the implementation plan: a two-environment protocol (cloud sessions author and never verify; Mac sessions verify and own every checked box), ten rules for Swift written without a compiler, continuous integration on a hosted macOS runner as the compiler for cloud sessions, verification batches, fifteen amendments to decision 026 (ownership, string additions files, a value-free `PresentationFacts` in a UI-free module, a budget-carrying result, gates 1, 2, 4, 5 and 11, the scope of principle 2, an overlay exception, a thumbnail gate, validation hosts), five waves with entry and exit criteria, a backlog of about 110 items (Q-01 to Q-181) with priority, effort, owner, Mac dependency and prerequisites, gates G13–G20, 27 owner decisions grouped by when they block work, risks and rejected items.
- `docs/validation/pending-mac-verification.md` starts the queue that cloud sessions append to and Mac sessions consume.
- `docs/reviews/2026-10-06-quality-review/owner-questions.md` writes the 27 owner decisions as questions with options, the lead's recommendation, what each answer unblocks and an answer line.
- `PLAN.md` gains the program section with the review box checked and the five wave boxes open, a risk-register row for Swift authored without a compiler, and a corrected header (76 formats, dated 2026-10-06). Decision 026 carries a dated note that 027 amends it.
- Not verified: everything. The first Mac session runs the Wave 1 agenda in decision 027 before any design is frozen.

## 2026-10-06 — Competitor UX/UI research and the world-class UX program (research and planning)

- Seven parallel research reports under `docs/market/ux-research/`, one per cluster, all against one rubric (preview anatomy, content presentation, interaction and discoverability, states and honesty, companion, native feel, trust communication, delight) with 1–5 scores and screenshot evidence: closest rivals, breadth leaders, code and Markdown, data and databases, folders/archives/3D, Apple's own Quick Look baseline with HIG and macOS 26 rules plus best-in-class Mac apps, and a code-level self-audit of SpacePane (32 findings, inconsistencies, a shortcut discoverability table, accessibility risks, a ranked top 20). About 150 App Store frames and the vendor-site and README images were downloaded and inspected. Every competitor statement is marketing material, not a test.
- `docs/market/2026-10-06-competitor-ux-ui-analysis.md` synthesizes them: headline findings, a per-dimension scorecard naming each leader and SpacePane's self-score, the table stakes, the openings where every competitor is weak, thirteen deduplicated patterns to adopt, the patterns rejected with the rule that rejects each, five owner decisions and the limits of the evidence.
- `docs/decisions/026-world-class-ux-program.md` records the proposed program: twelve principles, the preview anatomy contract (facts strip, mode control, info popover, one privacy row, muted ink tier, `NativeStateView`, limits strip, two densities), the companion page contract (hierarchy, neutral single-home status, setup trail, renderer pills, pinned Theme sample, Undo, Try Preview inspector), seven workstreams with disjoint file ownership, the shared contracts the lead adds first, twelve measured acceptance gates and what is not promised.
- `PLAN.md` gains the program section with the research boxes checked and every implementation box open. Nothing in the product changed.
- Landscape correction: Unfold's changelog lists 3.2.0 (2026-10-03) with interactive STEP previews and thumbnails although the App Store API still returns 3.0.2; the 2026-10-05 landscape now carries a dated note that STEP is no longer a SpacePane-only differentiator among general-purpose apps. IGES remains unmatched among the apps found.
## 2026-10-06 — Pin the en-GB short month so Safari hydrates the demo dates

- Fix (website only, `web/`). The demo Finder's absolute date stamps ("30 Sept 2026 at 19:48") threw a hydration error in Safari: JavaScriptCore abbreviates the en-GB September as "Sep" while V8/Node (current CLDR) render "Sept", so the server HTML and the client disagreed on the same locale.
- `src/lib/i18n/format.ts` pins the CLDR spelling for en-GB date locales: `formatCalendarDate` and `formatTimestamp` rewrite a word-boundary "Sep" to "Sept" after formatting (no effect on V8/Node output). The full/long date styles use whole month names and were verified to agree across engines. English, Kurmanji and Hausa all use the en-GB date locale, so they inherit the fix.
- Verified:
  - JavaScriptCore (Safari's engine, via `jsc`) prints "30 Sep 2026" and the pin turns it into "30 Sept 2026", matching Node.
  - A live check confirms the server HTML and the hydrated client cells agree (en-US and en-GB browser contexts, zero console errors), and the dev server log shows no new hydration failures.
  - `pnpm run check` passes.
- Not verified: other locale/engine month-abbreviation pairs are unchanged; they could in principle diverge the same way, but no case has been observed and the pin is scoped to the confirmed en-GB divergence.

## 2026-10-06 — Fluid Functionalism: motion tiers and the language menu

- Implementation (website only, `web/`). Two items from the Fluid Functionalism audit:
  - **Motion tiers.** `globals.css` gains three interaction-duration tiers (`--duration-fast` 80ms, `--duration-moderate` 160ms, `--duration-slow` 240ms) with one-tier-quicker exits (60/120/160ms). Interaction feedback now uses them: the pill button (press 60ms, rest 160/80ms), the header border and the nav-link hover (was an instant snap), the FAQ "+" rotation (was 200ms), the How-it-works step bodies (open/close was 500ms, now 80/60ms), the format filter chips (selection was instant, now 160ms), the demo-tour step color and the switcher trigger. Ambient reveal and artwork motion keeps its deliberate longer durations.
  - **Language menu.** The switcher is rebuilt on the Fluid Functionalism dropdown (`shadcn add @fluid/dropdown`, radix flavor): the hover highlight glides between the 14 language rows, the selection background springs to the active language and the checkmark draws itself; the popup enters on the fast tier and closes crisply. The menu is named for assistive tech ("Choose a language"), the rows are radio items on the 36px ladder, and the stock `dropdown-menu.tsx` was removed as unused.
- Registry support: `components.json` registers `@fluid`; framer-motion and `@radix-ui/react-dropdown-menu` / `@radix-ui/react-scroll-area` arrive with the install. `MotionConfig reducedMotion="user"` wraps the app in `_app.tsx` (pinned to "always" under `?capture`, so design captures stay still for JS-driven motion too).
- The FF surface/shadow/interaction tokens and type scale land in `globals.css`, mapped onto the SpacePane palette (paper → sand → surface ladder, the hairline as the shadow outline, ink-mix hover/active, brand focus ring). The registry's site-wide scrollbar restyle and its base `:focus-visible` rule were removed as out of scope. `web/DESIGN.md` documents the tiers, the token mapping and the vendored-file policy.
- Vendored-file exceptions, commented in place: `dropdown.tsx` forwards `aria-label` (the registry interface has no aria pass-through), and `eslint.config.mjs` disables the react-hooks compiler rules (`refs`, `static-components`, `set-state-in-effect`, `immutability`) for the FF-installed files only.
- Verified:
  - `pnpm run check` passes (data, locales, typecheck, lint; two warnings inside vendored FF files).
  - Live measurement: the menu glides under a real pointer (`data-fluid-hover-active-index` 1→5), rows are 36px with one `aria-checked` row, no console warnings; `audit.mjs` no longer reports the old interaction durations (140/200/250/300ms are on-token now; the remaining off-token entries are ambient art).
  - `visual:compare` for the header at 1440/375 gives the same result with the old and new switcher (1.50%/0.57% — pre-existing drift between `web/` and the static reference).
- Not verified: screen-reader and VoiceOver passes over the new menu. The demo Finder's date stamps threw a hydration warning in Safari (engine CLDR divergence, noticed during this work); fixed in the entry above.

## 2026-10-06 — New app icon: "Syntax"

- The owner chose concept 02, "Syntax", from 12 icon concepts on a review page. Its style follows a reference macOS icon pack, used only for style; nothing was copied from it. The icon shows pink, violet and blue code bars above a grey space bar on a white squircle body.
  - Each bar has a soft shadow tinted to its own color.
  - A hairline edge at 12% keeps the white body visible on light pages.
- The new mark replaces the old blue pane-and-bar icon everywhere:
  - `Website/assets/img/icon.svg`, the single icon source.
  - `web/public/images/icon.svg`, the Next.js site's copy, kept identical.
  - The macOS `AppIcon.appiconset`, regenerated from the source by `script/generate_app_icon.swift` (all 10 sizes).
  - On the sites, the icon appears in the favicon, header, footer, How it works store card and Themes "native" card.
- The floating icon in the Themes card had a blue glow tuned to the old icon. Both sites now use the site's `violet` token at 40% instead. `web/DESIGN.md` records the brand mark and the glow.
- The 64-unit SVG keeps the generator's grid: the body spans 2…62. It uses only paths, linear and radial gradients and gradient strokes. macOS's SVG renderer (used by `NSImage`) ignores blur filters, which was checked, so every shadow is a radial-gradient ellipse.
- Verified:
  - `xcrun swift script/generate_app_icon.swift --check` passes, and the 1024 px and 64 px renders look right.
  - `npm run check` passes in `web/`.
  - The served icon is the new file, there are no console errors, and the header, How it works and Themes captures show it.
  - `npm run visual:compare` for the header, How it works, Themes and footer, at 1440 and 375 px, gives the same results with the old and new icon. Both sites change together. The large Themes and footer differences already exist on `master`, because `web/` has moved on from the static reference.
- Not verified: the icon in an installed, signed build in the Dock and Finder.

## 2026-10-06 — Replace the read-only captions with an info badge

- Every preview began with two caption lines, "Read-only preview" and "Preview by SpacePane", above the mode control. They now live in the tooltip and VoiceOver label of a small `info.circle` symbol (`PreviewInfoBadge`) at the trailing edge of the header. No strings changed; the badge reuses `preview.readOnly` and `preview.interaction.providerBadge`.
- Where the badge sits:
  - With several modes, it shares the mode control's row, so nothing is left above the modes.
  - With a single mode, it starts the status row. That row keeps the badge's height even without notices.
  - It appears only while a preview is shown, as the provider caption did. Without a configured name, as in the Theme page's sample, the tooltip has only "Read-only preview".
- The status line now shows only notices about this document and collapses when there are none. The concealed-secrets notice stays visible as text, because it changes what selection and copying return. A hidden mode control no longer adds an 8 pt gap above the content.
- In a 450 pt dark preview, JSON content now starts directly under the Source/Outline row instead of under two caption lines and then the modes.
- [Decision 021](docs/decisions/021-preview-interaction-and-live-reload.md#provider-badge) records the change.
- Tests:
  - The two provider-badge tests now check the badge's tooltip and accessibility label: it is hidden in the loading, unavailable and disabled states, follows the provider name and shows names verbatim.
  - Two layout tests cover the two header arrangements.
- Verified:
  - Offscreen renders of a two-mode JSON file, a single-mode text file and a concealed `.env` file at 450 pt in Dark looked right; the snapshot test was removed afterwards.
  - The renderer tests pass: 927 tests in 92 suites.
  - `./script/build_and_run.sh --check` and `--check-compiler` pass. `--check-compiler` type-checks the app and both extensions against the changed package.
  - `./script/build_and_run.sh --test` exits 0: 2,452 Swift tests in the parallel run, 5 wall-clock tests in the serial pass, every integration check and 648 adversarial cases.
- Not verified:
  - Tooltip display inside the remote Quick Look view in Finder. VoiceOver reads the label, but a hover tooltip may not appear in a remote view.
  - Real VoiceOver and translated layouts.
  - The website still describes a "Preview by SpacePane" badge and draws a caption in its live demo; it was not changed here.

## 2026-10-06 — Adopt the Features tiles as the website's showcase card style

- Documentation only. The owner liked the Features section's bento tiles, so `web/DESIGN.md` gains "Bento capability tiles (preferred showcase style)": the grid, tile, per-tile accent pair, illustration stage, SVG drawing conventions, copy, chips and action, with pointers to the components and data. New feature or showcase cards should reuse it. No code or token changed.

## 2026-10-06 — Sort the website's languages alphabetically

- `web/src/data/locales.json` now lists languages alphabetically by their own names with the Unicode root collation, so the order is the same in every UI language: Bahasa Indonesia, Deutsch, English, Español, Français, Hausa, Kurmancî, Português, Türkçe, Русский, हिन्दी, বাংলা, 日本語, 简体中文. The language menu, the hreflang links and the Features tile follow it. Locale detection does not depend on the order.
- `npm run data:check` fails when the list is out of order. The language switcher falls back to the default locale instead of the first entry, which is no longer English.
- Verified: `npm run check` passes, the check fails on a swapped pair, and the language menu shows the new order in a dev server.

## 2026-10-06 — Showcase the Safety Lens and the parity features on the website

- Implementation (website only, `web/`). Six parallel workstreams on a shared contract laid by the lead (new demo modes, stub views, section anchors, sample placeholders), then five translation workstreams:
  - **Safety Lens section** (new, after How it works): hidden-content detector with a Source/Invisibles toggle, archive risk report, secret inventory with the sync-folder warning and Copy Concealed Text, notebook health, CSV/TSV Profile and CAD measurements. The mock banners quote the app's own finding wording. A "why now" strip links the primary sources from the market research, and the CAD card says measurements are approximations. No comparative or "only" claims.
  - **Live preview demo** now mirrors the app's Safety Lens: typed findings and a banner above the preview, the Invisibles mode (`⟨U+202E RLO⟩`, `⟨TAG ×N⟩`), decoded Unicode Tag text passed through concealment, secret inventory by kind with lines, archive risks for the sample and for dropped ZIPs (which now also read encryption, links and the executable bit), and notebook health. Also new: the CSV/TSV Profile mode (up to 10,000 rows; concealed columns show only their empty count), a native Mermaid Diagram mode (flowchart, sequence, pie; no scripts or HTML injection) and a "Preview by {{brand}}" status line. New samples: `AGENTS.md` (hidden characters stored as `\u` escapes), `experiment.ipynb`, `invoice-2026.zip`, `checkout.mmd`. The tour gains Hidden text and Diagram steps and its archive step shows `invoice-2026.zip`.
  - **Capabilities section** (new, before Formats): counts derived from the catalog and locale data (76 types, 309 distinct suffixes, 84 code languages, 11 color schemes, 14 interface languages) and a bento grid of the parity families, with links into the demo.
  - **Themes**: the eleven color schemes with separate Light and Dark pickers, `data-scheme` palettes from `NativeColorSchemes.swift` in `preview-theme.css`, store state, and every preview surface (panel, Finder pane, cards, 3D view) following them; High Contrast keeps Standard. DESIGN.md documents the mechanism.
  - **Copy**: refreshed meta, hero, how-it-works, privacy ticks, Native and FAQ copy; four new sample cards and an `AGENTS.md` hero tile; support FAQ for findings, false findings, the Quick Look conflicts scan and badge, live reload, color schemes and thumbnails; privacy policy sections on Safety Lens findings, Copy Concealed Text, live reload and the conflicts scan (effective date 2026-10-06). Navigation gains Safety Lens and Features.
  - Lead integration: the Quick Look panel's content is a column (banner, then a stage that fills the rest); the delimited parser takes an optional row budget; `agentRules: false` stops `next dev` from writing `AGENTS.md`/`CLAUDE.md` into `web/`; the Capabilities swatches use the real scheme palettes.
- Translations: about 350 new or reworded strings per language in all 13 non-English locales, following the app's String Catalog terms where they exist. All are drafts pending native-speaker review; Kurmanji and Hausa are lowest confidence. Chinese and Japanese keep the site's localized Quick Look and Finder names.
- Validation: `npm run check` (data, locales, typecheck, lint) and `npm run build` (70 pages) pass. In a dev server the demo was driven for `AGENTS.md`, `invoice-2026.zip`, `staging.env`, `orders.csv` (Profile) and `checkout.mmd` with no console errors, and the home page has no horizontal overflow at 375 px in English, German and Russian.
- Not verified: `npm run visual:compare` (the static `Website/` reference has no counterpart for the new sections), VoiceOver and keyboard-only passes, Safari/Firefox, and native-speaker review. The site describes app capabilities from package-level evidence; Finder-hosted behavior remains unverified as recorded in the validation records.

## 2026-10-06 — Accept QuickLookPro's file-type identifiers as optional aliases

- On the development Mac, `.jsonl` resolved to QuickLookPro's imported `com.quicklookpro.file.jsonl` instead of `org.jsonlines.jsonl`, so Finder never asked SpacePane and showed the generic icon. QuickLookPro's identifiers also won `.env` and several Markdown suffixes. Its extensions being turned off doesn't matter, because the type declarations come from the installed app.
- Per the user's decision, the catalog now lists the 179 QuickLookPro identifiers for suffixes it already supports, across 16 formats, as optional aliases. They load only where that app is installed, are never canonical, imported or exported, and match only their own format. Manifests were regenerated: 280 preview and 276 thumbnail types.
- Amended [decision 004](docs/decisions/004-json-lines-and-group-controls.md). `validate_project.py` now enforces the alias rules; a deliberate violation was rejected.
- Added a test that every loaded alias classifies to its own format and is never canonical. The `text.log` type test now ignores installation-dependent aliases.
- Verified `--check` and 2,450 package tests plus the companion checks.

## 2026-10-06 — Adopt the publisher's production identifiers

- Before any upload, replaced the generated local identity `com.canburaksofyalioglu.filepreview` with `org.webmeister.spacepane`. The user owns webmeister.org, and the identifier stays independent of the replaceable display name. Bundles are now `org.webmeister.spacepane` (app), `.preview`, `.thumbnail` and `.cad-import`. The App Group is `Z743N6D8DS.org.webmeister.spacepane.shared`, and the CAD helper signs as `org.webmeister.spacepane.CADWorker`.
- Renamed the app-declared imported content types to `org.webmeister.spacepane.type.*` in `FormatCatalog.json` and regenerated the three Info.plists with `script/sync_manifests.py`. Updated the tests and decision records that name them; validation records keep the identifiers that were actually tested.
- Development builds start with default settings once, because the new App Group container is empty. Remove old builds that use the previous identifiers before Finder checks, so two copies of the extensions aren't registered.
- `--archive` now unregisters and removes Xcode's intermediate copy of the archived app. Launch Services had registered its Quick Look extensions, so they competed with the development build in Finder; the check found and removed one such copy.
- Verified `--check`, 2,449 package tests and the companion checks. A signed Release archive passed `check_release_archive.py`; it was inspected for the four bundle identifiers, the App Group entitlement and the helper identifier.

## 2026-10-06 — Make the other adapter cancellation tests deterministic

- Merged `master` (PRs #5 and #6) into this branch. Three files conflicted:
  - `RequestContext`: master's new `nameHint` and `options` fields now sit beside `checkpointObserver`.
  - The JSON Lines cancellation test: master's fix cancelled as soon as the parse started. That made the race less likely but did not remove it, and the cancel usually landed before the parse began. This branch's version, which cancels at a known checkpoint, is kept.
  - This file: both sides' entries are kept.
- The delimited-text, text-art, SubRip and WebVTT cancellation tests had the same sleep-then-cancel race. They and the JSON Lines test now share one test helper, `CancellationTest.expectStopsActiveParse`, in `PreviewFormatsTests`. It parses once without cancelling and counts the checkpoints. A second parse cancels its own task at the middle checkpoint and must throw `CancellationError` there.
- The parse without cancellation must now succeed. That exposed three inputs that could never be parsed successfully:
  - SubRip had 240,000 lines and WebVTT 180,000, both over the 100,000-line budget.
  - The text-art input was a single 8 MB line, over the line-length budget.
  The old tests passed only while the cancel happened to arrive before the budget error.
- New inputs that fit the budgets:
  - SubRip and WebVTT: 20,000 cues each.
  - Text art: 13,000 code page 437 rows of 79 shade glyphs, each ending in CRLF.
  - Delimited text: 1,500 rows instead of 9,000.
  Size no longer affects whether the tests are deterministic. These sizes keep each test under 1 s in a debug build.
- `JSONLinesCooperativeCancellationStopsActiveLargeSource` left the serial wall-clock pass in `--test`, because it no longer depends on timing. That pass now has five tests, and the README says so.
- Not changed:
  - The Jupyter, notebook-health, archive-risk, ZIP, container and folder-listing cancellation tests wait until their task is cancelled before they start parsing.
  - The pipeline test's adapter never finishes.
  - None of these can lose a race. The 2 ms sleep in the image-pages decode probe is a polling gate that also checks for cancellation.
- Verified:
  - With `Task.checkCancellation()` removed from `checkpoint()`, all five tests fail both assertions. The line was restored afterwards.
  - The five tests passed together 20 times in a row (1.76–1.81 s per run).
  - `./script/build_and_run.sh --test` exits 0 on the final tree. Swift Testing reports 2,449 tests in 233 suites passed in the parallel run and 5 wall-clock tests in the serial pass. The settings, companion, file-drop, live-reload, SQLite and appearance checks pass, along with 648 adversarial cases.
  - Under that full-suite load, each converted test takes 6–9 s, well inside its 30 s parse deadline. This is package and model evidence only; it does not cover Xcode bundles or Finder hosts.

## 2026-10-06 — Merge the Safety Lens into the competitor parity work

- Merged `master` after PR #5 (Safety Lens, CSV/TSV Profile, CAD measurements). Both branches changed the pipeline contracts, container listings, preview modes, the preview view, summary labels and the string catalogs. The merge keeps both sets of features; the resolution is in [the program validation](docs/validation/parity-program-2026-10-05.md#integration-with-the-safety-lens-2026-10-06).
- ZIP listing now reads through the shared `ZIPArchiveReader`, with master's link targets, modes and risk report. RAR, 7z, and bzip2/xz TAR payloads are risk-assessed and list unsafe names as flagged text instead of failing, as ZIP and TAR do.
- Profile is offered only for CSV/TSV tables. The findings banner, Invisibles mode and Profile coexist with the new mode views, the accessory bar and the color schemes.
- The program's decision record moved from 012 to [025](docs/decisions/025-competitor-parity-program.md); 012 remains the Safety Lens.
- Verified after the merge: `--check` (924 keys), `--check-compiler`, and `--test` (2,454 Swift tests, every integration check, 648 adversarial cases) pass. Finder and signed-host behavior remain unverified.

## 2026-10-05 — Make the JSON Lines cancellation test deterministic

- `JSONLinesCooperativeCancellationStopsActiveLargeSource` slept 2 ms before cancelling an 11 MB parse. Under the full parallel test run it once resumed after the parse had finished, and failed. Changing the sleep or source size cannot fix this: the parse is synchronous, so no test code runs inside it.
- Shared-contract test seam: `RequestContext` gains a `package`-access `checkpointObserver`, called first in every `checkpoint()`. Only code inside the PreviewCore package, including its tests, can set it. The app and extensions cannot see it, and production never sets it. With no observer, a checkpoint does one extra nil check, so no format changes behaviour.
- The test now parses the source once without cancelling and counts its checkpoints. That count depends only on the source. A second parse cancels its own task at the middle checkpoint. The test checks that this parse throws `CancellationError` at that checkpoint, with half the work left. It never depends on timing.
- Check that it still catches a regression: with `Task.checkCancellation()` removed from `checkpoint()`, both assertions fail. The production line was restored afterwards.
- Follow-up: four other adapter cancellation tests (delimited text, text art, SubRip and WebVTT) still used the same sleep-then-cancel pattern. They were fixed on 2026-10-06 (see above).
- Verified:
  - The filtered `swift test --filter JSONLinesCooperativeCancellation` run passed 20 times in a row (0.63–0.74 s each).
  - `./script/build_and_run.sh --test` exits 0. Swift Testing reports 464 tests in 39 suites passed, and the companion-model, file-drop, appearance-interaction and adversarial-corpus checks pass. This is package and model evidence only; it does not cover Xcode bundles or Finder hosts.

## 2026-10-05 — Close the gaps found in the competitor landscape

- Implemented the [competitor parity program](docs/decisions/025-competitor-parity-program.md): twelve parallel workstreams on a shared prep commit, each with its own decision (013–024) and validation record, integrated and validated together. See the [program validation](docs/validation/parity-program-2026-10-05.md).
- The catalog grew from 31 to 76 formats and from 70 to 309 suffixes:
  - **Archives:** RAR 4/5, 7z (with an original bounded LZMA/LZMA2 decoder), bzip2, xz, JAR and WAR listings.
  - **Documents:** LaTeX, BibTeX (APA, MLA, Chicago and IEEE), AsciiDoc, reStructuredText, Org, Fountain, EPUB, FictionBook, CBZ comics and MHTML.
  - **Diagrams:** native Mermaid (flowchart, sequence, pie, state, class, ER) and draw.io.
  - **Packages and security:** `.app` bundles, IPA, APK/AAB, provisioning profiles, certificates, installer packages, disk images and torrents.
  - **Data:** Parquet (with row samples), Avro, Arrow/Feather, NumPy, HAR, GeoJSON, GPX and KML/KMZ.
  - **Code and text:** INI, logs, JSONC/JSON5, SubStation Alpha, TTML, SBV, LRC and MicroDVD captions, 84 language profiles and 181 source suffixes.
  - **3D:** STL, OBJ, PLY and 3MF on the existing viewer.
- New preview modes and tools:
  - **Modes:** Contents, References, Diagram, Pages, Icon, Files, Tree, Plot and Rows. A Mermaid fence in Markdown also opens in Diagram.
  - **Markdown:** task lists, footnotes, alerts, front matter, an approximation of math, and right-to-left paragraphs.
  - **Listings:** folder depth and hidden items, plus sortable and filterable tables.
  - **Interaction:** live reload, Go to Line, Copy All, outline filter and row copy, temporary zoom and a provider badge.
  - **Large files:** minified JSON is formatted for display, and the start of a large line-oriented text file is shown.
- Thumbnails can now draw concealed content for 41 formats, behind a new switch that is on by default. Sensitive formats keep the generic glyph, and STL, OBJ and PLY keep the system's own 3D thumbnails.
- Preferences schema 6 stores the new switches and eleven contrast-checked color schemes, with separate light and dark choices. The companion can list other installed apps whose Quick Look extensions overlap these types.
- Containers read under a 16 MiB, 5-second scan budget instead of the 1 MiB text budget. Output, node and line limits are unchanged.
- Shared tooling:
  - `script/sync_manifests.py` derives the Info.plist type lists from the catalog and runs in `--check`.
  - `tools/add_localizations.py` adds keys in all 14 languages at once.
  - `--test` runs six wall-clock tests in a separate serial pass.
  - `--check-compiler` no longer needs ripgrep.
- New system libraries: `libbz2`, plus the Security CMS and certificate APIs for inspection only. No third-party dependency was added. The color-scheme notices are in `ThirdPartyNotices/ColorSchemes/`.
- The 817 localization keys exist in all 14 languages as drafts.
- Verified on Apple silicon, macOS 27.2, Xcode 27.0:
  - `--check` and `--check-compiler` pass.
  - `--test` passes: 2,086 Swift tests plus every integration check and 648 adversarial cases.
  - The thumbnail extension builds with Xcode and links the system libraries.
  - The website's format data is regenerated.
- Not verified: Finder routing and thumbnails for any new type, the signed app and preview extension, sandboxed Security calls, provider scanning and live reload, VoiceOver, translated layout, native-speaker review, Release performance, macOS 15 and Intel.

## 2026-10-05 — Add the Safety Lens, the CSV profile and CAD measurements

- **Shared contract** ([decision 012](docs/decisions/012-safety-findings.md)):
  - Typed findings (kind, severity, count, displayed lines, typed detail) were added to the adapter, privacy and presentation models with empty defaults, plus one merge in the pipeline. Existing adapters and hosts are unchanged.
  - `LogicalLines` is now the single definition of a displayed line, shared by the gutter and findings.
  - A findings banner sits above every text preview, in the companion and in the Finder extension. Copy Concealed Text copies the whole concealed text.
- **Notebook health:** the notebook preview reports cells that ran out of order (with the sequence), gaps in execution numbers, cells that never ran, saved errors and a reproducibility hint. Nothing runs.
- **Archive risk report:** ZIP, TAR, GZIP-wrapped TAR and XIP listings now flag:
  - paths leaving the destination folder, and links pointing outside the archive;
  - apps and scripts, names that disguise their type or hide it with direction-changing characters;
  - encrypted and nested entries, extreme compression and very large totals;
  - hidden entries, names that differ only in capitalization, and `__MACOSX`.

  Each risky entry is marked in the Summary. **Behavior change:** `../` paths and encrypted ZIP members are now listed with a warning instead of failing the whole archive. NUL and control-character names, and central-directory encryption, still fail.
- **Secret inventory:** what was concealed, by kind and displayed line (private keys, cloud keys, code-hosting tokens, API keys, web tokens, authorization values, sensitive fields). A warning appears when such a file is in iCloud Drive or a `~/Library/CloudStorage` provider folder; the folder name is never shown.
- **Hidden-content detector:**
  - It reports direction-changing characters (Trojan Source), zero-width characters, Unicode Tags (the hidden text is decoded and concealed), stray variation selectors (GlassWorm-style), private-use characters, mixed-script look-alike words and Markdown comments that most viewers hide.
  - In AI-agent instruction files such as `AGENTS.md`, `CLAUDE.md`, `.cursorrules`, `SKILL.md`, `mcp.json` and `*.mdc`, it raises these to warnings.
  - A new **Invisibles** mode shows each hidden character as a marker such as `⟨U+202E RLO⟩`, while Source stays exact.
  - Expected uses are not flagged: emoji sequences, joiners in Hindi, Bengali, Arabic or Persian text, flags, ideographic variants, and direction marks in right-to-left lines.
- **Privacy fixes:**
  - Invisible characters typed into a key name (`pass<ZWSP>word = …`) no longer stop the value being concealed. One shared pattern and one concealment token now live in `SecretFieldPolicy`.
  - XML property lists now get the hidden-content scan.
- **CSV/TSV Profile mode:**
  - One row per column: type, missing values, distinct count, exact minimum and maximum, mean, most common values, an 8-bin distribution with a spoken description, and quality notes. The notes cover mixed types, leading zeros, date formats that differ, surrounding spaces and duplicate names.
  - Concealed columns show only their empty count.
  - The profile is computed lazily: 65–71 ms in Release for 20,000 × 64.
- **CAD measurements:** STEP and IGES previews add surface area, volume when the tessellated surface is closed, and body count. They also show the STEP schema or IGES version and the originating system. Author, organization and file name are never read. The 10 × 20 × 30 mm box fixtures measure exactly 2,200 mm² and 6,000 mm³ through the real worker.
- **Strings:** 107 new strings in all 14 languages (drafts pending native-speaker review). Format calls in the CAD view now use literal keys, so translations get placeholder checks. AGENTS.md gained one rule for findings.
- **Verified:** 832 package tests in 67 suites (from 464) and every `--test`, `--check` and `--check-compiler` gate. See [the validation record](docs/validation/safety-lens-2026-10-05.md).
- **Not verified:** signed companion or Finder display, VoiceOver and keyboard review, translated layout, macOS 15 and Intel. PLAN tracks these.
- **How it was built:** the lead defined the shared contracts and strings, then three waves of parallel Sonnet agents worked in isolated worktrees with disjoint files, followed by two translation passes. The lead reviewed and integrated every patch.

## 2026-10-05 — Add Finder's Preview pane to the website's live demo

- The live demo's Finder window now has Finder's Preview pane (View › Show Preview), laid out like macOS:
  - **Preview:** a miniature of SpacePane's presentation of the selected file fills the top. It is a scaled-down render through the same views as the Quick Look panel.
  - **Header:** the file name, then "Kind - Size".
  - **Information:** a section with a "Show More" link, then Created and Modified in full ("Friday, 2 October 2026 at 09:47"). Long values wrap onto a second right-aligned line.
  - **Tags:** an "Add Tags…" placeholder.
- The pane follows the selection from clicks, arrow keys, the guided tour, cross-section requests and dropped files. It also uses the chosen theme, mode and line-number setting. The 3D bracket turns slowly unless reduced motion is on.
- The sample files gained synthetic creation dates. Dropped files show only Modified, because browsers don't report creation time.
- Layout: the Finder window now fills the theater (1076px at desktop widths, was 940px), with a 280px pane. The Size column keeps at least 66px. The pane is hidden at 960px and below, so tablet and phone layouts are unchanged.
- Accessibility: the pane repeats the selected row and is `inert`. Its miniature controls are out of the tab order and hidden from assistive technology. Quick Look (Space) remains the interactive preview.
- Added seven strings (Information, Show More, Created, Modified, Tags, Add Tags…, and the "Kind - Size" pattern) in all 14 languages, using each macOS's Finder wording. Bengali, Hausa and Kurmanji keep English Finder labels, like their column titles.
- Product evidence: Finder's Preview pane showing SpacePane's preview has been observed for JSON and plain text ([installed host](docs/validation/installed-host-2026-10-04.md), [extensionless files](docs/validation/extensionless-files-2026-10-04.md)). Broader Finder-surface validation remains open in PLAN.
- Verified:
  - `npm run check` passes.
  - A Playwright run confirms arrows and Home update the pane, Tab skips it, Quick Look opens over it, and a dropped TOML file shows only Modified. The pane is hidden at 960 and 375px, with no overflow and no console errors.
  - The 84-load locale sweep is clean.
  - Screenshots of table, code, Markdown, folder, notebook and 3D previews look right in Dark and Light.
  - The pixel comparison with `Website/` is unchanged except the intended demo section at 1440px (2.95%, same dimensions); at 375px the demo still matches (0.05%).
## 2026-10-05 — Fix the Netlify deployment of the website

- The deployed site showed Netlify's "Page not found" for every URL because the publish directory was `web/`, which serves the source folder. Added `web/netlify.toml` with the build command `npm run build` (the lockfile is npm's), publish directory `.next` and `NODE_VERSION` 22. It overrides the UI fields; only the base directory `web` needs to be set.
- Netlify's Next.js runtime, `@netlify/plugin-nextjs` 5.16.1 (the latest), fails to build Node.js middleware. `replaceFunctionsConfigManifest` writes into `.next/server` before the directory exists, so the build fails with ENOENT; its Edge-middleware path creates the directory first. Moved the language routing from Next 16's `proxy.ts` (always Node.js) to `middleware.ts` (Edge runtime) without changing the logic. PLAN tracks moving back once the plugin is fixed.
- Excluded Netlify's local `.netlify` output from git, ESLint and TypeScript.
- Verified with `netlify-cli` 27.11.0:
  - `netlify build --offline` completes, and the middleware is packaged as an Edge Function.
  - Under `netlify serve`, the 24 language-detection checks, the browser language flow and the 84-load locale sweep all pass.
  - The pixel comparison is unchanged: every section is at most 0.20%, except the 375px headers (switcher only).
  - `next dev` still passes the detection checks.
- Not verified: the live Netlify deployment.
## 2026-10-05 — Research unique feature opportunities

- Added [unique feature opportunities](docs/market/2026-10-05-unique-feature-opportunities.md): 12 ranked proposals checked against the full text of 151 Quick Look app descriptions, competitor sites and targeted web searches.
- The recommended theme is a "Safety Lens": a hidden-content detector (invisible and bidirectional Unicode, Unicode Tags, variation selectors), an archive risk report, a secret inventory with a sync-folder warning and redacted copy, and a notebook health check. Next come a CSV data profile and CAD dimensions in Quick Look. Download provenance, Spotlight metadata and on-device AI need feasibility spikes first.
- Each proposal records evidence of need, uniqueness checks, feasibility, effort and risks, and suggests a typed "findings" presentation contract to be recorded in a decision first. Ideas competitors already offer, or that break the local-only and no-execution principles, are listed as rejected. Research only: no code, plan checkbox or product decision changed.

## 2026-10-05 — Research the Quick Look competitor landscape

- Added [the competitor landscape](docs/market/2026-10-05-competitor-landscape.md). It lists the features of 11 general-purpose Quick Look apps, 6 free or open-source projects and about 40 single-format specialists (code, Markdown, data, folders and archives, 3D/CAD, media and other).
- It includes a capability matrix against SpacePane, key findings (QuickLook Pro is the closest match; secret masking and per-type switches are not unique; STEP/IGES in a general-purpose app is the clearest differentiator; content thumbnails, RAR/7z and Markdown extras are the main gaps) and pricing context.
- Sources are vendor App Store descriptions (US storefront, via Apple's public search/lookup API), product sites, GitHub repositories and a TidBITS thread. Features are vendor claims, not tested; ratings were unavailable. Research only: no code, plan checkbox or product decision changed.

## 2026-10-05 — Open the website in the visitor's language

- English stays the default, unprefixed language. A request proxy (`web/src/proxy.ts`) now sends a visitor on any unprefixed page (`/`, `/support`, `/privacy`) to their language.
  - **Language choice:** the visitor's choice from the language switcher (`NEXT_LOCALE` cookie) comes first, then the best match for the browser's `Accept-Language`.
  - **Matching:** the proxy compares language and script, so `pt-BR`, `zh-CN`, `es-419` and `ku` resolve to the site's Portuguese, Simplified Chinese, Spanish and Kurmanji. Traditional Chinese and unsupported languages stay on English.
  - **Unaffected URLs:** prefixed URLs and files are never redirected.
  - **Redirects:** they are temporary (307), keep the query and hash, and responses vary on `Accept-Language` and `Cookie`.
- Turned off Next.js's built-in detection, which only handled `/` and missed regional variants such as `pt-BR`.
- `<html lang>` and `dir` now follow a client-side language switch. Next.js only sets them on server render, so before this change, switching from Turkish to English left screen readers on Turkish rules until reload.
- Added `npm run test:locale-detection`, 24 checks against a running server.
- Verified on the production build:
  - All 24 detection checks pass.
  - A Playwright flow passes: a Turkish browser lands on `/tr` and `/tr/support`. Choosing English keeps it on `/` and `/privacy` after reload. Choosing Deutsch sends `/support` to `/de/support`. `pt-BR` keeps `?open=…#demo`, and `ko-KR` and `zh-TW` stay English.
  - The 84-load locale sweep is clean.
  - The pixel comparison is unchanged.
- Limitation: Next.js removes the default-locale prefix before the proxy runs, so an explicit `/en/…` link follows detection like `/…`. The site never publishes `/en` URLs.
- After merging the extensionless-file format, I regenerated the website's format data in all 14 languages, so it now lists 31 types. I also regenerated the static `Website/assets/data/formats.json`, which master had left stale (its `--check` failed), so both sites stay comparable. The formats section still matches at 0.00%.
- The browser demo now treats a dropped file without an extension like the app does. It shows text as "Files Without an Extension", with likely secrets concealed, and reports other bytes as binary. Names such as `Makefile` and `.zshrc` resolve to Source Code through the new catalog aliases.

## 2026-10-05 — Rebuild the website with Next.js in all 14 languages

- Added `web/`, a Next.js 16 rebuild of the spacepane.com site:
  - Built with the Pages Router, React 19, TypeScript, Tailwind CSS 4, shadcn/ui primitives, next-i18next and Zustand.
  - It reproduces `Website/` pixel for pixel, with the same behaviour: the hero hand of files, How it works, the privacy slider, the live Finder and Quick Look demo with drop-to-preview, formats, themes, samples, FAQ, support and privacy pages.
  - `Website/` stays as the pixel reference until the new site is deployed.
- Structure follows `web/README.md`:
  - Routes only in `src/pages`, one folder per home section in `src/features/home/sections`, and the demo engine in `src/features/preview`.
  - Pure parsers, concealment and highlighting live in `lib/`, components in micro-folders, and shared primitives in `src/components/common`.
  - Cross-section UI state lives in a Zustand store with demo and appearance slices.
  - `web/DESIGN.md` records the design tokens (single source in `src/styles/globals.css`) and the styling rules.
- shadcnblocks bases were adapted and then removed:
  - feature197 became the How it works accordion.
  - careers12 became the format filter tabs.
  - pricing38 became the theme radio cards.
  - gallery11 became the samples carousel.
  - faq3 became the FAQ accordion.
  - navbar17 and footer50 supplied the header and footer structure.
  - The comparison base was not adopted: it had no keyboard support, so the privacy slider keeps the native range input.
- All copy and data come from JSON:
  - Copy is in `public/locales/<locale>/*.json` and data in `src/data/*.json`.
  - Translation keys are compile-time checked, the brand name is interpolated as `{{brand}}`, and identifiers are enums.
  - `scripts/sync-app-data.mjs` derives format names and descriptions in every language from the app's `FormatCatalog.json` and String Catalog translations. It also checks that the site's locales equal `tools/localization/languages.json`.
  - `scripts/check-locales.mjs` enforces key parity, per-language plural categories, placeholders and rich-text tags.
- Languages:
  - English is the default, unprefixed locale; the other 13 use prefixed URLs (`/tr`, `/zh-Hans`, …). Turkish was reviewed by the lead as the primary translation.
  - Every non-English translation is a draft pending native review; Hausa and Kurmanji have the lowest confidence.
  - App-screen names and the Quick Look/Finder terms follow the app's own translations.
  - Numbers, sizes and dates use `Intl`. Kurmanji and Hausa format with English conventions because Chromium ships no ICU data for them, which would make server and browser output differ.
- `/support.html`, `/privacy.html` and `/index.html` redirect permanently to the new routes, so the app's About links keep working. A visually quiet language switcher was added to the header, and pages gained canonical, Open Graph and hreflang metadata.
- Intentional differences from `Website/`:
  - **Format filter:** the browser's filter now actually filters. The static `.fmt { display: grid }` overrode `hidden`, so its chips never filtered.
  - **Plurals:** labels use correct plural forms ("1 row").
  - **MIDI canvas:** the piano roll resizes its canvas height too.
  - **Markdown:** a Markdown line containing U+2028 no longer hangs the demo parser.
  - **Dates:** English dates show CLDR's "Sept".
- Validated on Apple silicon, macOS 27.2, Node 26, Chromium 153 (Playwright):
  - **Checks:** `npm run check` passes (data sync, locales, `tsc`, ESLint) and `npm run build` prerenders 70 pages.
  - **Pixel comparison:** `tests/visual/compare.mjs` compares the production build with `Website/`. All 22 home sections and the support/privacy header, document and footer have identical dimensions. Every section is at most 0.20% different at 1440px and 375px, except the 375px headers (0.55–0.57%), which differ only by the language switcher.
  - **Locale sweep:** 84 production page loads (14 locales × 3 pages × 2 widths) gave no console errors, hydration mismatches, overflow, raw keys or untranslated home copy.
  - **Agent checks:** each section agent also checked interactions and logic against the original scripts. That covered concealment, highlighting, Markdown, CSV, outline budgets, ZIP listing and drop reading, the CAD mesh, and MIDI timing.
- Not verified:
  - Deployment and hosting.
  - Safari and Firefox.
  - Real touch devices and VoiceOver.
  - Native-speaker review.
  - The 961–1100px header in the longest locales beyond de, ru, fr, es, pt and ha.

## 2026-10-04 — Preview text files that have no extension

- Found the cause: macOS types every extension-free file as exactly `public.data`, which the product deliberately did not declare, so Finder showed a generic icon and the pipeline returned "unsupported".
- Added the `text.extensionless` format ("Files Without an Extension") with its own File Types switch. Only the preview extension declares `public.data`; thumbnails are not registered, so system icons stay. Root types are matched exactly, require a name without a suffix and are never conformance ancestors.
- The adapter shows only text (UTF-8, or UTF-16 with a mark) and reports other bytes as binary content. Scripts naming an interpreter are styled as source. Shell startup files and common build files (`zprofile`, `.zshrc`, `Makefile`, `Dockerfile`, …) are filename aliases of Source Code.
- Replaced the "no `public.data`" rule in AGENTS and `validate_project.py` with a single narrow exception, recorded in [decision 011](docs/decisions/011-extensionless-files.md). Executable-bit files are not covered.
- Added name and description strings in 14 languages (359 keys, drafts) and a sample and host fixture for the new format.
- Verified `--check`, 464 package tests, the fixture check and the signed build, and observed `zprofile`, plain text, a binary file and a JSON control in Finder Quick Look.
- On this host Finder had been launching a stale `Prev.app` 0.1.0 extension from Xcode DerivedData. Two stale registrations were removed with `pluginkit -r` and the current build re-announced; nothing was deleted and Finder was not restarted. See [validation](docs/validation/extensionless-files-2026-10-04.md).

## 2026-10-04 — Prepare the 1.0 build for Mac App Store upload

- Added the app icon. `script/generate_app_icon.swift` renders `Website/assets/img/icon.svg` onto Apple's 1024-pixel macOS icon grid, with the standard shadow, into `Apps/PrevApp/Assets.xcassets`. The app target compiles it as `AppIcon` (generator and project updated).
- Added the store keys uploads require: `LSApplicationCategoryType` (Utilities) and `NSHumanReadableCopyright`, both taken from `Branding.xcconfig`, plus `ITSAppUsesNonExemptEncryption = NO`. Raised the version to 1.0.0. Release builds are now Apple silicon only (`ARCHS = arm64`), because Intel execution and the x86_64 CAD worker are unverified. An Intel slice can be added in a later update.
- Signed the embedded CAD worker with the identifier `<owning bundle>.CADWorker`, as Apple's embedded-helper guidance asks.
- Removed prototype and signed-build wording from four customer-visible strings: setup steps, provider note, private-storage banner, and the unsupported-type message that Finder previews can show. Updated all 14 languages through the translation inputs; translations remain drafts.
- Added `Website/privacy.html` and `Website/support.html` with footer links, and pointed the About page's Support and Privacy Policy links at them. Both pages give support@spacepane.com as the contact; that mailbox must exist before the pages go live.
- Added `./script/build_and_run.sh --archive` and `script/check_release_archive.py`. They archive the signed Release app and check it for upload problems:
  - store keys and the compiled icon
  - quarantine attributes and architectures
  - nested signatures, sandbox entitlements and helper identity
  - bundled notices and dSYMs

  `--check` now also validates the category, copyright, encryption key and icon.
- Added paste-ready App Review notes and App Store Connect answers in [docs/release/app-store-submission.md](docs/release/app-store-submission.md). M6 in PLAN records the gates that remain open: page deployment and mailbox, Organizer validation, and the OCCT/CAD decision.
- Verified on Apple silicon, macOS 27.2, Xcode 27.0:
  - `--check` and 453 package tests, plus the companion, SQLite and adversarial checks.
  - Two signed Release archives passed the archive check; the resolved Info.plist and helper identifier were confirmed in the archive.
  - The three-bundle localization probe passed 33 cases.
  - macOS shows the icon in its standard shape.
  - The new web pages render at desktop and phone widths, and every internal link resolves.
- Not verified: Organizer Validate App, distribution export and re-signing, the deployed pages, and the Open System Settings link.

## 2026-10-04 — Show a sample of every file type in the Theme live preview

- Replaced the fixed JSON sample with a menu of every catalog format. Each choice shows a built-in synthetic item through the production pipeline and native renderer, so source code, Markdown, tables, outlines, archive listings, SQLite, MIDI and 3D models can all be seen with the current appearance. Appearance remains one global setting; per-format overrides are not part of this change.
- Added `script/generate_appearance_samples.py` and a bounded 30-sample manifest in the companion's resources. `--check` now fails if the catalog and samples differ. Samples are written to a private temporary directory per request and removed on close.
- Samples are shown even for a type turned off in File Types, with a caption saying so; the user's choices still apply to every real file. Recorded in [the appearance decision](docs/decisions/003-preview-appearance.md).
- Added two strings, reworded one and retired one in all 14 languages (357 keys); translations are drafts.
- Verified `--check`, 453 package tests, 11 companion model checks (including every text-presentation sample through the real pipeline), the signed build and offscreen renders of ten sample kinds. The signed app loaded its default sample; choosing other types in the real window was not exercised. See [validation](docs/validation/companion-redesign-2026-10-04.md).

## 2026-10-04 — Fix clipped sample cards and broken folded corners

- The samples carousel no longer scrolls vertically. `overflow-x: auto` made it a vertical scroll box as well, and the hover shadow overflowed it, so a trackpad nudge, or a lifted card, cut off the top edge and tag of the cards. It now sets `overflow-y: hidden` and gets 16px/44px of vertical padding, offset by matching negative margins, for the lift and the shadow.
- Removed the hover "peel" that scaled only the corner flap. The flap's diagonal stopped matching the fixed cut and showed as a detached square on sample and format group cards. Every file shape now has one static, matched dog-ear with a soft shadow under the flap.
- Reserved the formats row height (`min-height: 260px`) so the catalog cards, which load after the page, no longer push the content below them down.
- Verified in the in-app browser at 1200px: no vertical overflow (a forced `scrollTop` stays 0), and a hovered card is fully visible inside the carousel with its tag and corner intact.

## 2026-10-04 — Smooth the samples carousel hover

- Fixed the jumpy sample-card hover. A later `transition: transform .3s` overrode the folded-corner transition, so `--fold` snapped from 34px to 48px. Animating the corner also re-cut the card's `clip-path` and resized its pseudo-element every frame, the icon tile's `backdrop-filter` re-blurred while it moved, and spring overshoot plus rotation made small moves wobble.
- Hover now animates only `transform` and `opacity`: the card lifts on a single glide curve, a soft shadow in the card's own colour fades in underneath, a light sheen sweeps across, the corner peels by scaling its flap from the corner, the icon rises slightly, and the title arrow slides right. Hover effects apply only on devices with a real pointer (`@media (hover: hover)`). Format group cards got the same treatment.
- Added mouse drag-to-scroll to the carousel. Snapping pauses while dragging and settles on the nearest card, a drag is never treated as a click, and card text can no longer be selected while swiping.
- Verified in the in-app browser: running hover animations are transform/opacity only (plus the arrow colour), a 250px drag settles on the next card at 379px and isn't counted as a click, and a plain click still opens the sample.

## 2026-10-04 — Fix broken hover animations on the website

- Hero files no longer flicker. Hover used to lift the button itself, moving its hit area away from the cursor, and neighbours shifted their hit areas too. Measured with real cursor moves, hover toggled on and off within about 10 ms. Now a file's hit area never moves: an inner `.ftile__body` lifts and leans, and hover is tracked once for the whole hand with `pointerover`, so moving between overlapping files hands over cleanly. Keyboard focus lifts a file too.
- The scroll reveal no longer overrides hover states. Its final `transform: none` beat the theme cards' hover lift, it replaced elements' own transitions, and it left an inline `transition-delay` that delayed every later hover. Reveal now uses the individual `translate`/`scale` properties and a `--reveal-delay` variable, and the class is removed once the element has arrived.
- Keycap buttons draw their key edge with `box-shadow` instead of `border-bottom-width`, so pressing no longer changes their height or shifts nearby layout.
- Theme cards lift with `translate` and have a hit strip below them, so the lifted edge keeps the hover.
- Re-ran the cursor test: hover stays on the same file through small edge movements and moves straight to the neighbour. The theme card lift applies (`translate: 0 -5px`), button height stays at 42px, and there are no console errors.

## 2026-10-04 — Reshape the themes section gradient as a planet horizon

- Replaced the wide elliptical glow at the top of the dark Themes section with a huge navy circle (`max(240vw, 1600px)`). Its rim and blurred atmosphere carry the same palette as a conic gradient: amber at the crest, then magenta, violet and indigo along the arc. Faint stars are scattered inside. The colours are unchanged; only the shape is new.
- Checked at 1506px and 375px in the in-app browser, with no horizontal overflow and no console errors.

## 2026-10-04 — Fix the How it works art and refine website motion

- Fixed the collapsed Space key in step 3. Step art now fills its stage (`.art { width: 100% }`, a `minmax(0, 1fr)` art column), so percentage widths no longer shrink to the content and the scene fits at 375px.
- Rebuilt the steps as animated scenes. Install fills a progress bar; Turn it on switches both extensions on in sequence; Press Space loops a key press that pops a Quick Look window out of the selected row (pauses on hover, opens the live preview on click); Make it yours cycles the theme swatches. The accordion animates its height, and the scenes crossfade with a spring and blur. Collapsed bodies and hidden scenes are `inert`.
- Hero files deal out from the space bar on load. Neighbours lean away on hover, dragged files tilt with their momentum and spring upright, and clicked files pulse before the preview opens. The space bar flashes its glow and ripples the hand. Fixed the entrance replaying after a ripple.
- Added spring and ease tokens, registered `--fold` and `--pos` so file corners and the privacy slider animate. The slider sweeps once on first view, and Quick Look content crossfades on file and mode changes. The panel opens with a spring, theme cards lift and their badge pops, and scroll reveals soften with blur. Reduced motion keeps a static, fully visible state.
- Verified in the in-app browser with no console errors: step scenes, switch sequence, a frozen Quick Look frame, deal-in, hover nudge, drag tilt and release, the space-bar ripple and open, and the 375px layout.

## 2026-10-04 — Redesign the website as a light editorial page

- Rebuilt `Website/index.html` and `assets/css/site.css`. A user-supplied landing page was the starting point, then the design was pushed away from it: warm paper and navy palette, keycap buttons, serif italic headline accents, a dotted Finder-grid hero, folded-corner file cards, alternating split cards, an indigo-to-amber "space bar" glow instead of a teal dome, and a gradient wordmark footer.
- The hero is a fanned hand of nine draggable sample files above a large space-bar key. Clicking a file or the key opens that sample in the live preview.
- How it works is an auto-advancing accordion with step illustrations, including working toggles and a pressable key. Privacy has a slider comparing SpacePane's concealed view with the raw file.
- Presentation cards render real scaled-down previews: a CSV table, a concealed `.env` file and an auto-spinning 3D bracket (`mountCad({ autoSpin, compact })`).
- The live preview sits in a dark theater with an eight-step guided tour that auto-advances while visible and stops on any visitor input (`initQuickLook(..., { onUserAction })`).
- Formats show five catalog groups as file cards that open a filterable browser. Themes use the app's real choices (Follow System, Light, Dark, High Contrast), replacing the invented Graphite/Paper/Dusk names, and restyle the live preview. A samples carousel opens more files in the demo.
- Verified in the in-app browser: no console errors, tour advance, opening files from tiles, the space bar and the carousel, theme application, keyboard Space/Escape, a TOML drop with concealment, and no horizontal overflow at 375px. Captured the desktop page into the Figma file (node 19:2). Font replacement and variable binding in Figma were not done because the Figma plan's MCP call limit was reached.

## 2026-10-04 — Add the spacepane.com website with a live preview demo

- Added `Website/`, a static, build-free landing page for spacepane.com. It covers the hero, how-it-works, a feature bento, formats, privacy, themes, FAQ and the App Store call to action. App Store availability is shown as "coming soon", and no price, languages or unverified platform support are advertised.
- Added an interactive Finder/Quick Look demo. Arrow keys and Space work as in Finder, the panel zooms open from the selected row, and per-type modes are offered (Outline/Source, Table, Rendered, Notebook, Cues). It includes 14 synthetic sample files covering text, JSON, CSV, Markdown, notebook, subtitles, diff, YAML, env, Swift, ZIP, SQLite, folder, MIDI with playback, and a shaded 3D STEP stand-in with orbit/zoom/standard views.
- One locally dropped file is previewed in the browser and never uploaded. Detection uses the catalog's extensions, filename aliases and prefixes; ZIP central directories are listed with bounds; formats without a browser presentation say so. Multiple or folder drops are rejected without replacing the current preview, mirroring decision 006.
- Ported the default concealment rules (`SecretFieldPolicy` keys and `DefaultPrivacyFilter` value patterns) to `Website/assets/js/conceal.js`. Sensitive JSON keys and CSV columns are concealed in every view. File contents reach the DOM as text only, and remote Markdown images and links are never loaded. Keep the port in step with the app.
- `Website/tools/generate_formats.py` derives `assets/data/formats.json` from `FormatCatalog.json` and the English String Catalog; `--check` fails on drift. Added the `website` launch configuration (`python3 -m http.server 4173 --directory Website`).
- Verified in the in-app browser: every sample and mode renders without console errors, keyboard selection and Space/Escape work, theme/size/line-number controls restyle both previews, and simulated drops of ZIP, JSON, `.env.local`, SQLite and multi-file input behave as described. The 375px layout has no horizontal overflow, and touch devices get a tap hint. Real-device Safari, VoiceOver and touch review remain open.
- Captured the 1440px page into the Figma file's new "Website — spacepane.com" page. Rebuilt the hero heading in auto layout and added the sixth bento tile there and in code. Replaced the unavailable SF Mono with JetBrains Mono (the CSS fallback) in 119 text nodes. Added a "SpacePane Web" variable collection (12 colors, 2 radii, with WEB code syntax) and bound 228 matching fills and 13 radii. The Figma capture script is not left in the page, so the site loads no third-party scripts. `?open=<sample name>` opens a sample on load, and `?capture` disables scroll reveals for future captures.

## 2026-10-04 — Rename the product to SpacePane

- Set the display and executable name to SpacePane and the website to spacepane.com in `Configuration/Branding.xcconfig`. The built app is now `SpacePane.app`, its extensions are named SpacePane Preview and SpacePane Thumbnails, and About shows a Website row.
- Kept every technical identity: bundle and App Group identifiers, imported type identifiers, Xcode project, targets, source directories, module names, the `PREV_` build-setting prefix, preference keys and stored settings. No migration is involved, and saved file-type choices and themes are unaffected.
- No localized string contained the old name; all copy receives the display name as a placeholder. Updated AGENTS, README and PLAN wording; historical research, validation and changelog entries keep their original wording.
- Passed `--check` and the signed build. Observed the renamed app directly: window, sidebar, app menu, About, every page, and immediate sidebar/menu changes when Developer Mode is toggled. See [validation](docs/validation/companion-redesign-2026-10-04.md).

## 2026-10-04 — Redesign the companion around a sidebar and add Developer Mode

- Replaced the six grouped tabs with a fixed sidebar in the same singleton window: General, File Types, Theme and About. Setup moved into General, Supported Files into File Types, Customization into Theme and Help into About. Command-comma selects File Types; About and Help select About.
- Added Developer Mode on General, off by default and stored only in the companion's own defaults. Try Preview, Open File, Command-O and Command-5 exist only while it is on; turning it off closes the preview session so a hidden file cannot be reread.
- Rebuilt every page from shared page, card, row, status-pill and two-column layout components. File Types is one catalog-driven table with collapsible groups, tri-state group checkboxes, counts and status; Theme keeps every appearance control beside one framed live sample; About shows version, help, privacy, the real acknowledgement and optional configured links.
- Kept status wording truthful: the app reports where settings are saved and how many types are enabled, never that Finder uses this provider. Prototype controls without real backing (extension switch, cache and Finder actions, updater, feedback form, configurable limits) were left out and are listed in [decision 010](docs/decisions/010-companion-sidebar-redesign.md).
- Added optional `PREV_*_URL` branding settings with `https`/`mailto` validation; all are empty, so no link is shown. Added `version`, `build` and `links` to `HostedConfiguration`.
- Added 59 string keys and retired 9 across the 14 languages (356 keys); new translations are drafts pending native-speaker review.
- Verified `--check`, 453 package tests, 10 companion model checks, the file-drop, SQLite, appearance and adversarial checks, the signed build and 33 three-bundle language probes. An independent read-only review led to seven fixes. Layout was reviewed only in offscreen renders; the real window, the System Settings link, VoiceOver and keyboard access remain unverified. See [validation](docs/validation/companion-redesign-2026-10-04.md).
- Updated AGENTS, README, PLAN and the single-window decision. Parser, preference schema, extension code and Finder routing are unchanged.

## 2026-10-04 — Implement and validate opt-in CAD previews

- Added independent, default-off IGES/STEP catalog choices with upgrade/reset/Enable All coverage and localized controls in the 14 draft languages. Restored both temporary test opt-ins to off through the companion Settings tab.
- Added a numeric-only validated mesh contract and additive geometry pipeline, pinned OCCT helper, bounded binary decoding, cancellation/deadline termination and lazy registrations. Native Metal navigation draws on demand and releases hidden GPU resources; ordinary formats and generic thumbnails never import CAD.
- Resolved Finder's direct-child sandbox restriction using an independently sandboxed, extension-embedded XPC service with a configured peer-signing requirement, bounded concurrent imports and no queued file data. Added host-managed remote-view visibility and tested viewport focus/drag/lifecycle handling without weakening sandbox protections or changing Finder preferences.
- Passed 239 Swift tests including real Metal rendering, the existing model/drop/appearance/SQLite checks, the 192-case policy/parser corpus, 11 native CAD checks, all 24 production-pipeline fixtures and 33 three-bundle language probes. Both final signed development builds succeeded; graph validation rejects 19 malformed identity/embedding/entitlement variants.
- Observed actual shaded STEP/IGES geometry in signed Finder Quick Look with the companion stopped, including the supplied private 720-face/27,335-triangle model, standard-view controls and close/reopen behavior. Also verified the model and view/zoom controls in the companion's existing tab. Source contents remained unchanged; private geometry was not copied into the repository or uploaded.
- Updated architecture, build/dependency instructions, plan checkboxes and [validation evidence](docs/validation/cad-previews-2026-10-04.md). Physical gesture/keyboard host QA, broader OS/hardware/accessibility/language review, full performance measurements and distribution-license gates remain open; automated input did not reliably target the remote Finder view.

## 2026-10-04 — Add required IGES and STEP CAD scope

- Identified the user-supplied 4.30 MB file through local read-only IGES record inspection; documented curved/trimmed-surface evidence without adding the private model or its personal/company metadata to the repository.
- Promoted IGES/STEP from general CAD feasibility candidates to explicit required 3D previews, with independent toggles, native navigation and the existing single-window/local-processing rules.
- Added primary-source feasibility research and concrete importer, mesh-contract, cancellation, resource, privacy, licensing and Finder acceptance gates. Current text-only presentation and standard input limits require deliberate shared-boundary changes; no importer dependency or runtime file-type declaration was added, and no geometry-rendering support is claimed.

## 2026-10-04 — Native renderer performance continuation

- Profiled the existing Release renderer with synthetic JSON Lines. Found substantial work in repeated outline expansion and layout/restyling of hidden source text; kept the measured fixtures and benchmark stages unchanged.
- Deferred hidden source materialization and styling until Source is selected, while clearing prior-generation text immediately. Added three failing-then-passing regressions for deferred style application, summary-first rendering and replacement/disabled-content clearing; existing native interaction checks pass.
- Characterized and corrected an existing canonical-Unicode equality bug in source/mode/outline invalidation. Renderer-local comparisons now retain exact safe source code units when canonically equivalent text is replaced; no parser, file decoding or public contract changes.
- Added native outline identity, batched root updates, reusable cells with cleared stale accessibility hints, and a shared per-pass semantic attribute map. Characterization rejected a bulk expansion shortcut that changed hierarchy behavior.
- Reran the unchanged 420-sequence Release benchmark: warm JSON Outline switching 193.784 → 15.956 ms p95, JSON Lines Records 563.839 → 70.755 ms, ZIP/SQLite initial summaries 74.360/176.106 → 16.237/28.603 ms. Recorded all cases, including the higher Markdown initial p95 and remaining initial-source/whole-request/memory targets, in [the performance report](docs/validation/native-renderer-performance-2026-10-04.md).
- Final verification passed 196 Swift tests, all isolated model/drop/appearance/SQLite checks, the 176-case corpus, project/localization checks and 33 three-bundle language probes. Both signed development builds passed. Observed concealed Source/Records in the singleton companion and Source/Outline in the newly rebuilt, attributed Finder extension with the companion stopped; both synthetic source hashes stayed unchanged.
- Updated repository guidance, README and granular plan checkboxes. Initial text/JSON/JSON Lines/source useful-content targets and broader release/platform/language/accessibility gates remain open.

## 2026-10-04 — Parallel host, UI, language and security quality pass

- Added a reproducible 22-format synthetic host fixture generator and production-pipeline/hash verifier. Observed all 22 in Finder with the companion stopped: 18 app presentations and four routing exceptions. Recorded and subsequently repaired the MIDI sound-bank preflight failure; audible-output, thumbnail-surface and OS/hardware checks remain open.
- Fixed XML CDATA and processing-instruction assignment concealment, plus immediate cancellation/deadline checkpoints in TAR/XIP. Added adversarial adapter, same-size mutation, cumulative GZIP and cyclic-plist regressions and a deterministic 176-case all-format corpus; integrated the corpus into `--test`.
- Added owned, cancellable theme transfer, model-level duplicate profile rejection, cancellation-preserved direct previews and localized stepper accessibility values. Integrated five isolated appearance checks. Added typed Command-1…6 tab shortcuts and observed existing-window navigation and successful Open-sheet cancellation without losing safe content.
- Corrected four technical translation values in German, Indonesian and Hindi; added seven translator notes, regional/fallback/source-preservation tests and an explicit signed-bundle resource checker. Every selected language remains a draft until speaker and actual-host review.
- Verification passed 184 Swift tests, five companion-model groups, five appearance groups, three drop groups, the independent SQLite check, 176 adversarial cases, 22 original fixture/hash checks, 13 localization-tool tests and 33 signed-bundle language cases. Both canonical and registered signed Debug builds succeeded; the final bundle-resource probe was repeated successfully.
- Diagnosed and fixed the Finder MIDI failure caused by a direct filesystem bank preflight disconnected from the initialized DLS unit. Optional public bank metadata no longer gates playback; retained actual audio errors, no extra entitlements. Thirteen targeted MIDI checks passed, including silent audio hardware lifecycle; the rebuilt Finder host passed Play/Pause/scrub/resume/end and visibly concealed the XML regression fixture. Audible note quality remains open.
- Added Release native-rendering measurements beyond the earlier core-only benchmark. Recorded timing/memory limitations and open optimization work instead of claiming target compliance. Updated plan progress, language selection wording and validation reports while preserving earlier uncommitted work.

## 2026-10-04 — Interaction and validation continuation

- Added a shared catalog-derived filename summary for Supported Files and Settings, including exact names and prefixes such as `package.json` and `.env.*`, locale-aware list formatting and meaningful accessible format hints. Five isolated companion-model check groups now cover identity preservation and localized list wording.
- Observed concealed YAML and Markdown plus expandable ZIP summaries in Finder after native companion quit, with unchanged synthetic sources and the signed provider identity recorded in [interaction validation](docs/validation/interaction-continuation-2026-10-04.md). Kept cold lifecycle, broader routing, drag grants and accessibility gates open.
- Fixed outline Copy interception outside responder focus, lost selection during appearance refresh, redundant accessibility labels and enabled unloaded/cleared MIDI controls. Added seven meaningful native interaction checks, including new-generation reset, safe Markdown copy and inert links.
- Added a standalone Release pipeline benchmark with eight synthetic cases, separate new-process and warm request distributions, bounded sample counts, process RSS and source-integrity checks. Recorded 480 measured requests on this Mac; these measurements do not establish Finder/renderer performance or the macOS 15/Intel matrix.
- Hardened localized format validation against repeated/mistyped positional arguments and unsupported directives; share it with the merge tool, preserve literal percentages in text-only copy, and run 13 focused tool tests from `--check`.
- Final verification passed 169 Swift tests, five companion-model groups, three drop groups, the independent SQLite lock check, 13 localization-tool tests and the signed Xcode build. Observed translated German Setup/Settings and exact filename patterns; minimum-width resizing remained blocked by the UI tool.
- Reconfirmed that Customization inspection crashes the automation service while the companion remains alive; no app behavior was changed to hide that tool failure.

## 2026-10-04 — Parallel baseline expansion

- Expanded the catalog from 3 to 22 independently controlled logical types, with exact filename/prefix classification and synchronized imported manifests. Added lexical code highlighting, JSON/JSONL source/outline/records, safe YAML/TOML subsets, environment/package summaries, inert native Markdown, diff/XML/plist/strings/OPML, SQLite, archives, folders and MIDI. Actual restrictions and remaining host gates are recorded in [expansion validation](docs/validation/parallel-expansion-2026-10-04.md).
- Added shared binary, bounded random-access and directory input capabilities under the existing disabled-format, cancellation and privacy gates. ZIP/TAR/XIP can inspect bounded ranges of larger files; malformed archive lengths are checked before arithmetic/allocation. SQLite receives a private read-only byte snapshot and uses a narrow owned public-API C safety shim; busy/live-WAL/sidecar states decline. Added an independent-process locking/no-write regression check.
- Added safe native secondary presentations, schema-path-localized generated metadata, exact JSON number spelling/duplicate flags, wholly concealed malformed JSONL records and record-count provenance for line-collapse fallback. Escaped configuration keys and uncertain complex syntax fail closed. MIDI exposes bounded channel events only, explicit playback and teardown; sound-bank discovery has an explicit unavailable fallback.
- Added strict schema 5 appearance persistence/migration, semantic token color/bold/italic, up to 32 named profiles and bounded inert JSON theme transfer. The companion uses user-selected export access through the existing window's system sheets; extension permissions and source readers remain read-only. Connected syntax settings to both companion and Finder rendering and stopped audio on tab/host changes.
- Selected English, Turkish, German, French, Simplified Chinese, Japanese, Hindi, Kurmanji Latin, Russian, Indonesian, Bengali, Hausa, Portuguese and Spanish. Added typed localized summary keys, per-language translation inputs and strict merge/resource/placeholder/metadata validation. Translations remain drafts pending native-speaker and actual-host review.
- Extended CLT compilation/linking to include internal C-target objects/module maps; retained the user's Xcode project instead of regenerating it. Updated repository guidance, checked implementation progress, README and the binary/language decisions.
- Built the signed app and both extensions; visually verified concealed JSON outline and rendered Markdown in the singleton companion. Rebuilt an obsolete development artifact to remove its placeholder registration, then attributed modern thumbnail-generator requests to the configured signed extension, including with the companion stopped. Customization inspection still crashes the automation service, not the companion; its GUI audit and broader platform matrix remain open.

- Final verification passed 162 package tests, four isolated companion-model groups, three private-pasteboard drop groups, the cross-process SQLite check, all three host compiler checks and a signed Xcode build. All three bundles contain 14 metadata and renderer localizations with matching sandbox/App Group entitlements.
- Added cumulative plist output preflight and regression fixtures for repeated binary references, plus ZIP/XZ overflow boundaries. Declared all localized metadata outputs in each sandboxed Xcode build phase and added drift validation.
- Observed Portuguese and Spanish Setup launches. Fixed translated tabs disappearing into toolbar overflow by choosing native grouped tabs in the existing singleton window; all six labels remain visible at the default size. Full language/layout review remains open.

## 2026-10-04 — Direct file drop and installed-host validation

- Added a localized, adaptive single-file drop strip in Try Preview. A focused AppKit adapter checks drag metadata, reads native file URLs synchronously and invokes the existing preview session; multiple/web/ambiguous drops do not replace the current preview. No parser, settings or extra-window path was added.
- Added three private-pasteboard check groups, including deferred-data-provider proof that hover reads metadata only. All 90 package tests, four companion model checks and three drop checks pass; 107 localization keys validate and the signed Xcode build succeeds. Observed the instruction in the UI and safe JSON Lines via keyboard Open. Real Finder drag grants, rejection feedback and full accessibility remain open in [drop validation](docs/validation/direct-file-drop.md).
- Observed a fresh, concealed JSON Finder preview with the companion stopped and source bytes unchanged. Recorded JSON Lines/plain-text routing differences and the unsuccessful attribution of thumbnail output to our provider, keeping those gates open.
- Confirmed the repeat Customization inspection failure belongs to SkyComputerUseService; no companion crash or app source defect was established. Corrected singleton-window lifecycle wording without changing app behavior.
- Updated architecture guidance, README, decisions and checked plan progress while preserving host-specific routing and tool limitations.

## 2026-10-03 — Single-window tab navigation

- Applied the user's explicit single-window requirement, superseding the earlier separate Settings scene and sidebar layout. All companion screens now share top-level tabs, including Settings and Customization.
- Routed settings, help and About actions to the same main window; retained shared preview/settings ownership and the existing bounded file-processing pipeline.
- Added typed localized Settings, Customization and brand-aware About labels. Updated repository guidance, README, the navigation decision and plan checkboxes.
- Verified a signed Xcode build, 90 package tests, four companion model checks and 105 resource keys. Observed Settings shortcuts/buttons, About and Help in the same window, attached file selection and retained JSON across tab changes; the File menu has no New Window action. Customization's native inspection failure remains an explicit GUI-validation gap in [navigation validation](docs/validation/single-window-tabs.md).

## 2026-10-03 — Repair local shared-settings configuration

- Diagnosed the screenshot against the registered signed extension: its Info.plist and entitlement still used `group.invalid.example.previewprototype`, which the runtime intentionally rejects before reading source files.
- With the user's authorization to generate identifiers, created ignored `Configuration/Local.xcconfig` using brand-independent bundle IDs and a macOS team-prefixed App Group, reusing the existing development team. Preserved the user's Xcode project edits and existing private prototype settings.
- Added a separate localized configuration/container-access message; corrupt/unreadable saved settings retain their recovery message. The fail-closed policy remains intact.
- Built and verified the signed companion and both embedded extensions with full Xcode; checked matching signed App Group entitlements. Observed shared settings save success, native mixed state, Finder disabled JSON, then a successful Space-bar JSON preview after restoring enablement.
- All 90 package tests, four companion model checks, three host typechecks and 102-key resource/project validation pass. Updated README, local configuration guidance and PLAN; recorded limits in [shared-settings validation](docs/validation/shared-settings-configuration.md). Thumbnail invocation and complete lifecycle/OS/accessibility checks remain open.

## 2026-10-03 — JSON Lines, grouped controls and line numbers

- Added independent JSON Lines/NDJSON source previews using the existing bounded pipeline and shared JSON scanner. All records validate before display; privacy ranges and node budgets span the full file. UTF-8/BOM policy, malformed records, aliases, cancellation and no-source-mutation have focused fixtures/tests.
- Retained BOM provenance in the decoded-text contract and added explicit imported/optional catalog types. Static manifests, prototype imports and localized type metadata are validated against the catalog. Generic conformance matching now prefers a narrower declared ancestor over text, preventing policy bypass; Finder routing remains a separate gate.
- Added catalog-derived native mixed group controls with explicit search-hidden scope, atomic snapshot publication and preserved unrelated/global choices. Added optional logical line numbers and strict schema 4 migration preserving schemas 1–3 values.
- Kept gutter labels outside text storage, selection, find and copy. Appearance now uses one adaptive control/sample tree. Renderer geometry checks exposed a scroll-ruler inset issue; the gutter uses explicit layout space instead.
- Added four repeatable checks compiling the actual companion models with isolated storage: safe-content retention after source deletion, group atomicity, corrupt-settings repair and failed-save retry. The existing test entrypoint runs these after package tests; object discovery is shared with prototype staging.
- Updated repository guidance, decisions, README and validation tracking. Verified 90 package tests, four actual companion model checks, 101-key/static metadata checks, all three host typechecks and prototype build/launch. Observed JSON Lines in Supported Files; Settings inspection still crashes SkyComputerUseService while the app remains alive and preferences remain unchanged. See [continuation validation](docs/validation/json-lines-and-controls.md); signed Finder, macOS 15 runtime and shipping-language gates remain open.

## 2026-10-03 — Preview appearance continuation

- Added system/light/dark/high-contrast preview themes and font family, size, weight, italic, line/character spacing, ligatures, tab width and wrapping, with an inert live sample in a separate native Appearance settings tab.
- Added complete schema 3 appearance snapshots and schema 1/2 migrations that retain file-type choices. Reset Appearance leaves those choices intact; same-value resets can repair corrupt storage or retry failed saves without reenabling content.
- Added semantic syntax hints from adapters through redaction to rendering. JSON coloring uses only concealed text, preserves characters and is capped by UTF-16 length and token count. Fixed repeated numeric rescanning during review.
- Appearance-only changes retain loaded safe content, selection and viewport. Fixed unwrapped document sizing, deferred zero-width layout, and explicit preview backgrounds for forced-theme contrast. Missing fonts/traits display localized fallback guidance.
- Added 34 typed localization keys (93 total), a Unicode/long-line fixture, and behavior tests for migration, typography bounds, contrast, font fallback, token ranges, bounded scans and native text/layout preservation.
- Verified all 57 tests, project/resource validation, all three host typechecks and companion build/launch. Visually confirmed colored/redacted JSON. Full settings GUI checks remain open because the UI inspection service crashed while inspecting Appearance; the companion remained running and original preferences were unchanged.
- Updated `AGENTS.md`, `PLAN.md`, `README.md`, the [appearance decision](docs/decisions/003-preview-appearance.md) and [validation report](docs/validation/appearance-slice.md). Signed Finder, multilingual release and remaining customization gates stay open.

## 2026-10-03 — Initial text/JSON implementation

- Added five SwiftPM library targets for domain contracts, orchestration, format adapters, preferences and native rendering. Text and JSON adapters share injected policy, bounded reading, typed outcomes and a serial worker per retained pipeline.
- Implemented UTF-8/BOM-marked UTF-16 decoding, bounded JSON source validation preserving number spellings/duplicate keys, conservative shared secret concealment and explicit unavailable/disabled states. Descriptor checks reject nonregular files and final-component symlinks; cancellation/deadlines remain cooperative.
- Implemented stable-ID file-type choices, versioned atomic preferences, migration and disabled-content recovery. Fixed first-run missing-file handling and prevented content reads before saved preferences load.
- Added a native companion with setup/help, direct file opening, supported-file information and searchable individual/all-type controls; added thin preview and generic content-free thumbnail extension sources.
- Added canonical String Catalog resources with typed lookup, deterministic fallback generation and localization validation. Initial English resources are development coverage; multilingual release remains open.
- Added a deterministic three-target Xcode project, explicit registration/sandbox configuration, centralized replaceable branding, ignored local signing overrides, a build/run/check entrypoint and Codex Run action. No production identity or signing configuration was invented.
- Added core/format/preferences/localization tests and `README.md`; recorded actual environment, implemented limits and pending signed-host checks in `docs/validation/platform-spike.md`. Added a narrow alias to the public SwiftUI State property wrapper to avoid the selected SDK's unavailable macro plugin without replacing SwiftUI state semantics.
- Configuration, catalog/manifest and 59-key localization checks pass. Full Xcode bundle compilation is blocked by the selected Command Line Tools environment; final integrated test/compiler/prototype results are recorded in the validation report.
- Verified `./script/build_and_run.sh --test`: all 33 tests pass, including Unicode newline budget regressions, special-file rejection, multiline concealment, atomic preferences and resource fallback. Added the selected-toolchain CLT Testing plugin/framework workaround; its native build-system deprecation warning remains documented.
- Added a companion-only Command Line Tools build with private settings, ad hoc signing and no embedded extensions or sandbox/App Group entitlements. Fixed module-owned resource lookup to prefer standard app `Contents/Resources` bundles instead of relying on SwiftPM build-cache paths; verified with a staged-resource regression test.
- Type-checked all three hosts with Swift 6 complete concurrency checking. Launched the prototype and visually verified synthetic JSON concealment, clearing of active content when JSON is disabled, and restored redacted content after resetting choices. Finder installation remains unverified.
- Moved companion pipeline construction to the app composition root so windows share one retained serial parser worker, and gave file-type switches explicit localized accessibility labels after UI inspection.

## 2026-10-03 — Country-specific pricing boundary

- Recorded the user's clarification that country-specific plans mean regional prices. Updated `PLAN.md` and `AGENTS.md` to place published pricing/availability in App Store Connect and policy/release verification in the repository.
- Distinguished paid-upfront pricing from an optional future one-time in-app unlock. If the latter is selected, StoreKit supplies display prices; no hardcoded country-price table or locale-based purchase-country inference is allowed.
- Added unchecked release configuration and storefront validation gates with current Apple source links. No amounts, countries, subscriptions, feature tiers or App Store configuration were created.

## 2026-10-03 — Multilingual product requirement

- Updated `AGENTS.md`, `PLAN.md` and the UI/UX report to require internationalization of all app-authored visible text, including accessibility, failure states, graphics and supported bundle metadata across the companion and both extensions.
- Specified pluralization, translator context, locale-aware metadata formatting, fallback, text expansion and RTL validation while preserving file contents and technical identifiers.
- Added unchecked implementation/release gates for language selection, cross-bundle resource resolution and complete reviewed translations in at least two real languages. The specific shipping language set remains undecided; pseudolocalization alone does not meet the requirement.
- Documentation only; no translations, app builds or runtime localization checks are claimed.

## 2026-10-03 — Typed references and localized strings

- Added repository rules and a plan requirement for localized user-facing resources, typed identifiers/errors/settings, generated asset references where available, and framework symbols instead of repeated raw strings.
- Kept unavoidable literal definitions at their owning schema/configuration/API boundary, with explicit protection for persisted identifiers and user content. Avoided a global constants container or unnecessary wrappers.
- Added an unchecked implementation gate for app/extension resource resolution, localization behavior and targeted reference checks. Documentation only; no implementation or runtime localization validation is claimed.

## 2026-10-03 — Provisional app name and replaceable branding

- Confirmed that Prev is a provisional name. Updated `AGENTS.md` and `PLAN.md` to centralize display names, localized branding copy and assets while keeping modules, format IDs and persisted preferences independent of branding.
- Distinguished a display-name change from changes to technical bundle/App Group identity; added an unchecked implementation/rename verification gate covering retained file-type choices and themes.
- Documentation only; no app was renamed or implemented. Validated Markdown links, fences and whitespace and confirmed implementation tasks remain unchecked.

## 2026-10-03 — User-controlled file types

- Added `docs/decisions/002-file-type-controls.md`: searchable individual/group/all-type controls, stable format IDs, persistent defaults and overrides, reset behavior and upgrade semantics. Disable All also keeps newly introduced formats off.
- Updated `PLAN.md`, `AGENTS.md`, the extensibility workflow and the technology/UI/synthesis reports. New formats gain standard settings rows and policy through the shared catalog, independently of decoder reuse.
- Specified one policy shared by previews, thumbnails and the companion that blocks content parser construction for disabled types, including generic/source fallbacks. Added unchecked implementation, persistence, accessibility, disabled-parser and real-Finder validation gates.
- Recorded the macOS boundary: switches control Prev's handling, do not rewrite static registration or guarantee provider handoff, and cannot promise immediate removal of cached previews/thumbnails.
- Validated all 11 Markdown files for local links, balanced fences, whitespace and conflict markers; confirmed the plan has 9 completed research/requirement items and 66 open implementation items. Reviewed toggle semantics across the architecture and UX documents.
- These are planning changes only; no application code, build, runtime test or implemented toggle is claimed.

## 2026-10-03 — Modular format architecture requirement

- Made modularity and separation of concerns the highest-priority architecture rules in `AGENTS.md`, with explicit SRP, DRY, KISS, YAGNI, open/closed and dependency-inversion guidance.
- Added `docs/decisions/001-format-extensibility.md` with domain/adapter/rendering boundaries, dependency direction, a standard format-addition workflow and a practical extensibility proof.
- Updated `PLAN.md` with domain contracts, explicit lazy adapter registration, shared policy/presentation components and unchecked implementation/conformance-test gates. New formats should normally require adapter, catalog/registration and fixture changes without modifying host or orchestration logic.
- Kept runtime plugin loading and speculative frameworks out of scope. These changes define implementation requirements; no application code or runtime validation is claimed.

## 2026-10-03 — Initial research and implementation plan

- Completed the five requested research reports and a sixth decision-synthesis report in `docs/initial/`.
- Added `PLAN.md` with the completed research checklist, accepted architecture, full baseline feature mapping, phased implementation work, acceptance gates, provisional performance/resource targets and risk register.
- Added the complete 116-entry plugin/package inventory: 94 entries with GitHub evidence, 8 with vendor/author evidence, 13 qualified unavailable/unverified entries and 1 without a supplied source URL.
- Reconciled cross-report preferences storage into one atomically published App Group document with a single companion writer; retained independent flags only in shared defaults.
- Added the macOS API report, including exact content-type routing, App Group/sandbox boundaries, missing-content limitations and modern extension lifecycle checks.
- Corrected XIP planning to distinguish its outer XAR table from inner PBZX/CPIO contents. Strengthened archive byte/decompression budgets and SQLite source-sidecar nonmutation checks after technical review.
- Added Apple HIG and UI/UX reports covering native surface ownership, setup, customization, keyboard/accessibility behavior, privacy and unavailable-file states.
- Expanded `AGENTS.md` with implementation boundaries, dependency review, verification requirements and accurate Finder support reporting.
- Added the technology-stack report with the native hybrid recommendation, dependency candidates, explicit concurrency boundaries, provisional performance budgets, and prototype gates.
- Initialized a local Git repository; no commit or remote was created.
- Added repository guidance in `AGENTS.md`, including plan completion and change-history rules.
- Created `docs/initial/` for the five requested research reports.
- Confirmed the starting directory has no application code, Swift package, Xcode project, or existing Git repository.
- Validated all nine Markdown documents for presence, local links, fence balance, conflict markers and trailing whitespace; checked inventory IDs/evidence totals and confirmed all implementation milestones remain unchecked.
- Completed final cross-report review with no critical documentation issues remaining; full baseline scope, privacy boundaries and runtime uncertainties remain explicit.
- No application source, dependency installation, signed extension, application build, runtime test or benchmark was produced in this research phase. No commit or remote was created.
