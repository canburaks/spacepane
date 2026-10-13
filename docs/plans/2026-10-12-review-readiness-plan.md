# Review readiness plan

Date: 2026-10-12. Status: **in progress. The source work of Phases 1 and 2 was done on 2026-10-12 and is uncommitted; nothing was uploaded or pushed. See the execution record at the end.** It continues the [App Store publication plan](2026-10-10-app-store-publication-plan.md) from the point that plan stopped (build 1.0.0 (1) uploaded, nothing validated on an installed store build) and replaces its Phases 3 to 7 for the remaining work. Paths are relative to this repository unless a sibling repository is named.

## Goal

A second build and a repository in which everything an App Review reviewer or a customer can see is true and has been observed on a store-signed install, so that submitting is a mechanical step. Concretely: the binary ships only what is reviewed and cleared, every claim on the store page maps to a recorded observation, the review notes can be followed by someone who has never seen a Quick Look extension, and no document in `docs/release/` contradicts the state of the app or of App Store Connect.

## Where things stand

From the audit of 2026-10-12 (five parallel repository audits and a read-only pass through App Store Connect). Facts, not plans:

| Area | State |
|---|---|
| Build 1.0.0 (1) | Processed, "Ready to Submit", zero installs, not attached to the version. Built from a tree that no longer matches `HEAD` (no Aurora scheme). |
| Binary | Sandbox on every bundle, no network entitlement, hardened runtime, privacy manifests present, versions and identifiers consistent, arm64 only, no external packages. No blocker found. |
| Languages | All 14 `.lproj` sets are in the app and both extensions; 13 are unreviewed drafts. The store page lists every bundled language. |
| CAD notices | The bundled `OCCT-Notices/NOTICE.txt` says "This development build" and that store licensing is "unresolved"; the public `SOURCE-OFFER.md` says "pending legal review… no release may rely on it". Decision 027 D20 has no recorded outcome. |
| Evidence | Finder preview observed for 4 of 76 types, the Quick Look panel for 23, Finder thumbnails for none, all on one development-signed Mac running macOS 27.2. macOS 15, the declared minimum, has never run the app. The CAD peer requirement has not met a store-signed SpacePane build. |
| Store page text | Entered and within limits. It names formats that were never observed in Finder (Markdown in the subtitle; CSV, RAR, 7z, Mermaid, EPUB, the mesh formats in the description). |
| App Store Connect | Missing: screenshots (0 of 10), the build selection, review notes and attachment. Not done: Paid Apps Agreement (status "New"), Digital Services Act trader status, publishing the App Privacy answers. Set: name, subtitle, categories, age rating 4+, content rights, copyright, review contact, price USD 9.99 in 175 regions, support and privacy URLs. Release option is "automatic", against this plan's "manual". |
| Website | Support, privacy and marketing URLs live; the contact address is `info@spacepane.com` everywhere. The privacy page says the site sets no cookies, but the language switcher sets one. |
| Mirror | `spacepane-cad-source` is one commit and the tag `1.0.0-build.1` ahead of its public remote. |
| Records | Several release documents are stale (listed in Phase 2). |

## Owner decisions

Work in Phase 1 cannot start on the first three until they are made. Each has a recommendation.

| ID | Decision | Recommendation | Why |
|---|---|---|---|
| R-1 | Languages in 1.0 (D-B, D22) | **Applied 2026-10-12 under the owner's standing rule that only reviewed languages ship:** English only, because no review is recorded. Add a language in a point release when its review is recorded. | Zero reviews exist. It is the rule already written in `AGENTS.md`. Thirteen draft languages on the store page are thirteen promises a reviewer or customer can test. |
| R-2 | STEP and IGES in 1.0 (D-D, D20) | **Decided (owner, 2026-10-13): they do not ship in 1.0** ([decision 028](../decisions/028-no-cad-in-version-1.md)). Open Cascade answered the owner's question without confirming or rejecting the source-offer route and pointed to its paid exception. The earlier recommendation was: Name a cut-over date now. If counsel has cleared the source-offer route by then, ship CAD with final notice wording; if not, 1.0 ships without the helper and CAD returns in 1.1. | The notice text cannot honestly be made final while the route is unreviewed, and the bundled text is what a reader sees. App Review does not judge LGPL compliance; this is a publishing risk, not a review risk. |
| R-3 | Minimum macOS (D-I, D21) | **Decided (owner, 2026-10-12): a macOS 15.2 (24C101) virtual machine was created with VirtualBuddy.** It is inside the 15.0 to 15.3 window that D21 names. **Owner, 2026-10-12: treat the app as working on macOS 15.** No session observed the run and the host matrix has no macOS 15 row; the review notes state it on the owner's word. | Raising the minimum to the only tested system (27.2) would exclude most customers; shipping 15.0 unrun is an unmeasured launch risk. |
| R-4 | Release option | Manual release. | App Store Connect is currently set to automatic. Manual lets the website link, the mirror tag and the release happen together. |
| R-5 | Category | Keep Utilities primary, Developer Tools secondary; close listing decision 5. | Build and store record already agree. |
| R-7 | TestFlight | **Decided (owner, 2026-10-12): internal TestFlight testing only.** No external testers and no public link. | Internal testing needs no beta review and is the only way to install a store-signed build before release (D27). External testing would also wait on the OCCT opinion. |
| R-6 | App name risk | Keep "SpacePane for Quick Look"; keep fallbacks B and C ready to paste. | Already decided (listing decision 1). Only the response to a rejection needs preparing. |

## Phase 0 — Account steps (owner, start today)

These have lead times outside the project and block submission regardless of the build.

1. Sign the Paid Apps Agreement, then complete tax and banking. The price is already set; the app cannot be sold until the agreement is active.
2. Declare trader status under the Digital Services Act (App Information, "App Store Regulations & Permits").
3. Send a message to `info@spacepane.com` from an outside address and confirm it arrives and can be answered. Mail records exist; delivery is unproven.
4. Optional: resolve the GitHub billing block so the hosted macOS job can run again.

## Phase 1 — Build 2 (Mac session, compiler required)

Every item runs `./script/build_and_run.sh --check` and the package tests before it is committed. Tests first where a seam exists.

1. **Ship list for languages (R-1).** `tools/localization/languages.json` gains a per-language review record and a `shipped` list (additive, so the website's sync script keeps reading `languages`). `script/build_metadata.py` emits `InfoPlist.strings` only for shipped languages; `Packages/PreviewCore/Package.swift` excludes the other `.lproj` resources; `Prev.xcodeproj` loses the pruned outputs; the three Info.plists get `CFBundleLocalizations`. `script/check_release_archive.py` fails when the archive's `.lproj` set differs from the ship list in any of the three bundles. Draft translations stay in the repository. Amend `AGENTS.md` so "the chosen language set" and "the shipped set" are distinct.
2. **CAD route (R-2).** Either branch ends with text that is true:
   - *Cleared:* rewrite `ThirdPartyNotices/OCCT/NOTICE.txt` (no "development build", no "unresolved", no `.build/cad` sentence), the status line and open-questions section of `Native/CADWorker/SOURCE-OFFER.md`, and `docs/dependencies/occt.md`; record the clearance in a decision record.
   - *Not cleared by the cut-over date:* add one build setting that omits the CAD helper, the XPC service and the two catalog entries; remove the Open CASCADE paragraph, the STEP and IGES mentions and keywords from the listing; keep the code in the repository. This is the several-hour project edit the publication plan anticipated.
3. **Defects seen while capturing screenshots.** `deploy.yaml` shows "Structured view is unavailable" (YAML outlines are named in the description); headings overlap in the Contents rail; Theme tiles have no accessibility labels and ignore accessibility presses; the test `figuresAndCoversAreNamedLikeTheirAccessibilityLabels` fails. Fix or, for a named format, remove the claim.
4. **Release-critical rows of `docs/validation/pending-mac-verification.md`:** the dataless-file guard, host session and timeouts, the privacy fixes, thumbnail admission, the About notice rows. Replace "verification pending" with evidence or revert the change.
5. **macOS 15 load check (D21).** Inspect the built binaries for symbols unavailable on 15.0 (`dyld_info -imports`), and record the result. A finding here returns to R-3. Static result for build 1.0.0 (1), 2026-10-12: `_swift_task_deinitOnExecutor` is a weak import in the app and both extensions (absent from the CAD service), so a missing symbol does not stop the binary loading; every call site (13 in the app, 10 in the preview extension, 9 in the thumbnail extension) follows a runtime version test with the constants 15 and 4, with a compiler-generated path for older systems. That the test is a macOS 15.4 availability check is read from the constants, not from a named symbol, and the older-system path has not run. The run in the 15.2 virtual machine is the evidence; repeat the static check on build 2.
6. **Review sample archive.** A script target that builds `SpacePane-Review-Samples.zip` from `script/generate_host_fixtures.py` and `script/generate_store_demo_files.py`, with a README, synthetic secrets only, and a check that every file named in the review notes is inside it.
7. **Hygiene from the publication plan:** remove the hard-coded `DEVELOPMENT_TEAM` from three targets; produce a dSYM for `CADWorker`; set `CURRENT_PROJECT_VERSION = 2`.
8. **Color scheme count.** `HEAD` has Aurora, so build 2 has twelve schemes. The listing and screenshot 09 follow in Phase 5.

## Phase 2 — Records agree with reality (no compiler; parallel with Phase 1)

1. `docs/release/app-store-listing.md`: remove "No build has been uploaded"; add a column to the claim table mapping each named format to its catalog ID, so Phase 5 can be checked mechanically.
2. `docs/release/app-store-submission.md`: drop the superseded rule against Apple names in the app name, the `support@` address and the "build 2 was used by the dry run" line.
3. `docs/release/publishing-roadmap.md`: mark it a historical snapshot at the top; correct "no MX record".
4. `docs/release/store-listing/listing.en.md`: delete it or reduce it to a pointer; it is superseded and still carries an owner-decision placeholder.
5. `docs/release/store-listing/app-store-connect-worksheet.md`: replace the review-contact placeholders with "entered in App Store Connect on 2026-10-12" (no phone number in the repository); tick only what the audit observed.
6. `PLAN.md`: tick nothing without evidence; add a pointer to this plan.
7. In `spacepane-web` (its own commit): correct the cookie sentence on the privacy page; after item 1 of Phase 1, run `npm run data:sync` and change the "14 interface languages" claim to the shipped set.
8. Regenerate `spacepane-cad-source` with `script/package_cad_source_offer.py` after Phase 1 item 2, tag it for build 2. Pushing waits for the owner's instruction.

## Phase 3 — Validate build 1 now

Build 1.0.0 (1) can be examined today, before build 2 exists, in two ways. Each result goes into `docs/validation/host-matrix.json` with its host and signature recorded; virtual-machine rows say so.

- **Internal TestFlight (R-7):** an internal group with the owner as its only tester and build 1 enabled; install on macOS 27.2 and, if the App Store and TestFlight work there, in the macOS 15.2 virtual machine. This is the store-signed install.
- **Development-signed copy:** the app inside `.build/archive/Release.xcarchive` carries the development signature, no provisioning profile and no restricted entitlement, so it runs on any Mac; it is the same compiled code that `--export` re-signs for the store. A zip made with `ditto` installs it in the virtual machine whether or not TestFlight works there. It tests loading and Finder behaviour, and only the team branch of the CAD peer requirement.

What to observe:

- `codesign -d -r-` on the installed preview extension; enable STEP and IGES and preview one of each. On the TestFlight install this closes D27.
- The exact path to enable both extensions on each system, word for word, for the review notes; the companion's "Open System Settings" button lands there.
- Finder preview, the Quick Look panel and Finder thumbnails for every format the listing names, using the files in `.build/vm-test/` (later the review sample archive).
- No App Group consent prompt; the window opens with content on first launch; closing and reopening the window works.
- VoiceOver and keyboard access in the companion and in a Finder-hosted preview.

Findings feed Phase 1.

## Phase 4 — Upload build 2 and repeat

On the owner's explicit instruction, with the key values in the shell only: `--check`, `--archive`, `--export` (inspect the re-signed bundles), `--upload`. Record Apple's processing result and every validation message verbatim in `docs/validation/`. Enable build 2 for the internal group and repeat the Phase 3 observations on it. A failure returns to Phase 1 with a new build number.

## Phase 5 — The store page says only what was seen

1. Cut or reword every claim whose catalog ID lacks a store-signed Finder observation (D-J). The subtitle counts.
2. Retake any screenshot whose scene changed (the theme page at least) from the validated build with `script/store-screenshots/`; confirm each Finder scene exists on the store build.
3. Fill the review notes in `docs/release/app-store-submission.md`: build number, tested systems, the enable path for each system, exact sample file names, how to switch on STEP and IGES and why they are off by default, why `public.data` is declared, what the `com.quicklookpro.*` aliases are, what Developer Mode is, that no account exists. Stay under 4,000 bytes.
4. Prepare replies for the foreseeable objections, each a short paragraph in the same document: minimum functionality (4.2), "the app only has settings" (2.1), the name (5.2.5, with fallback B ready), `public.data`.
5. Optional: a screen recording of under a minute showing enable, select, Space.

## Phase 6 — App Store Connect

Entered by the owner, or by a session in the browser pane on the owner's instruction, from the documents above:

- Upload the screenshots; select build 2; answer the export-compliance prompt.
- Paste the review notes; attach the sample archive.
- Publish the App Privacy answers ("Data Not Collected").
- Set the release option per R-4.
- Compare the English (U.K.) text with the U.S. text after Phase 5.
- Leave the accessibility label as a draft unless Phase 4 supports more than "Dark Interface".

## Phase 7 — Submit, then release

Recheck Apple's current requirement pages on the day. Add for review and submit only on the owner's explicit instruction. Record App Review's messages verbatim. After approval: release, replace "Coming soon" on the website with the store link, push the mirror and its tag on instruction, and record the released build in `CHANGELOGS.md`.

## Separate track — making this repository public

Not needed for App Review and not part of the critical path; listed because the owner intends it. It needs: a chosen `LICENSE`; a `README.md` written for an outside reader, with build instructions that work without `Local.xcconfig` values; a pass confirming no credential, key identifier, private model or phone number is in the tree; and a decision on whether the validation and review records under `docs/` are published as they are. The repository becomes public only on the owner's explicit instruction, and the pre-split history is never pushed.

## Work split

The lead owns `Prev.xcodeproj`, `Configuration/**`, `Package.swift`, `script/build_and_run.sh`, `script/check_release_archive.py`, `PLAN.md`, `AGENTS.md`, `CHANGELOGS.md`, integration, and every command that reaches Apple. Agents own disjoint files.

| Stream | Owns | Waits for |
|---|---|---|
| A. Language ship list | `tools/localization/**`, `script/build_metadata.py`, localization validators and tests | R-1 |
| B. CAD notices or CAD removal | `ThirdPartyNotices/OCCT/**`, `Native/CADWorker/SOURCE-OFFER.md`, `docs/dependencies/occt.md` | R-2 |
| C. Defects | the renderer and companion files of Phase 1 item 3, with their tests | none |
| D. Review samples and notes | the sample-archive script, `docs/release/app-store-submission.md` | Phase 4 for the final wording |
| E. Records | the rest of `docs/release/**` | none |
| F. Website | `spacepane-web` (separate repository and commit) | stream A for the language count |

Streams C and E can start at once.

## Done when

- The archive's languages equal the ship list, and its notices contain no statement that licensing is unresolved.
- Every format named on the store page has a store-signed Finder observation in `host-matrix.json` on macOS 27.2, and an observation on macOS 15.
- The review notes have no placeholder and every file they name is in the attached archive.
- `./script/build_and_run.sh --check` and the package tests pass with no known failure; no release-critical row is pending.
- App Store Connect shows screenshots, build 2, published privacy answers, review notes with the attachment, an active Paid Apps Agreement and a declared trader status.
- No document in `docs/release/` contradicts another or the store record.

## What this plan does not establish

- Whether App Review accepts the name, the `public.data` declaration or the app's scope. The plan prepares answers; it does not predict the outcome.
- Whether the source-offer route satisfies the LGPL for a store-signed helper. That is counsel's question.
- Whether the App Store and TestFlight work inside the macOS 15.2 virtual machine. If they do not, macOS 15 evidence comes from the development-signed copy, and the store-signed evidence from macOS 27.2 only.
- Whether results in a virtual machine match real hardware. Graphics are virtualized there, so 3D rendering and timings are not evidence for a real Mac.

## Execution record, 2026-10-12

The owner instructed: fix what is needed, and assume the app works on macOS 15. Four parallel agents and the lead did the work below in the working tree. Nothing is committed, nothing was uploaded, and no repository was pushed.

Done, with the check that shows it:

| Plan item | What was done | Evidence |
|---|---|---|
| Phase 1.1, languages | `languages.json` has `shipped` (`en`) and `reviews`; `build_metadata.py` emits shipped languages only and refuses a shipped language without a review record; the project declares only those outputs; the three Info.plists list `CFBundleLocalizations`; `check_release_archive.py` refuses any other top-level `.lproj`. | 82 archive tests pass (9 new); the build 1 archive now fails the check for its 14 languages; a local Release archive of 1.0.0 (2) passes it, with `en.lproj` only in the app and both extensions. |
| Phase 1.1, runtime | Draft translations stay inside the package's resource bundle. A nested bundle follows its host's language set, so they are unreachable. | An experiment on macOS 27.2: a host with `en` only returned English from a nested bundle holding `en` and `de` with German preferred, and German once the host carried `de`. Physical pruning was not done: the script sandbox forbids editing the copied bundle in place. |
| Phase 1.2, notice | `ThirdPartyNotices/OCCT/NOTICE.txt` states facts only: what is used, where, and where the source and the offer are. The local mirror was regenerated. | `package_cad_source_offer.py --check` and `mani run mirror-drift` pass. |
| Phase 1.3, YAML | The outline rejected any concealed scalar (`key:••••`), so an ordinary file with one `password:` line fell back to source; it now accepts it. A sensitive key whose value is only a comment (`auth: # c`) left its nested block visible; it now conceals what follows. Bounding a sensitive key's block by indentation was written and withdrawn after two reviews each reproduced inputs that left part of a secret visible; the old conceal-to-the-end rule stays. | A nested mapping with a concealed scalar gets its outline through the real pipeline; the comment-only case failed first in both stages; every input from both reviews is a regression test. |
| Phase 1.3, Contents rail | Rows grow to hold wrapped headings, measured against the current clip width with one measurer, and are tall enough at the largest font size. | `ContentsRowHeightTests`. |
| Phase 1.3, Theme tiles | An extra accessibility wrapper stripped the press action from the scheme tiles. Removed. | On a built companion, each tile reports a name, a selected state and `AXPress`, and pressing selects the scheme. |
| Phase 1.3, failing test | `figuresAndCoversAreNamedLikeTheirAccessibilityLabels` depended on the display scale. It is a test defect; the test now holds at 1x, 2x and 3x. | Full suite below. |
| Phase 1.6, review samples | `script/build_review_samples.py` builds a deterministic archive of 35 synthetic files with a README, and `--check` ties it to the review notes. Both are in the static gate. | 29 tests; `--check-static` 23 passed, 1 skipped. |
| Phase 1.7, hygiene | Build number 2; no hard-coded team in the three targets. The CAD helper was rebuilt in this checkout (its caches named the folder from before the split). | `validate_project.py`; `build_cad_worker.py --test`, 13 tests. |
| Phase 2, records | The release documents agree with App Store Connect as read on 2026-10-12; the claim table maps each claim to catalog IDs and host-matrix values. | `--check-static`. |
| Phase 2.7, website | On the local branch `review-readiness-copy` of `spacepane-web`: the privacy page describes the one language-choice cookie; the home page says version 1.0 ships in English with 13 translations drafted. | `npm run check` and `npm run build` pass there. |
| Phase 5.3 and 5.4 | Review notes complete (2,911 bytes, no placeholder) and four prepared replies, in `docs/release/app-store-submission.md`. | `build_review_samples.py --check`. |
| Whole tree | `--test`, `--check`, `--check-static`, `--archive`. | 3,724 tests passed with the 2 known issues, then the 74 serial tests and every integration check; the archive check passed for 1.0.0 (2). No export or upload was run. |

Not done, and why:

- **R-2, STEP and IGES.** Still the owner's decision. `Native/CADWorker/SOURCE-OFFER.md` still says "pending legal review… no release may rely on it", and that file is public. Shipping build 2 with CAD while that sentence stands is a contradiction only the owner can resolve: record that the route is accepted and reword the status, or cut CAD from 1.0.
- **dSYM for `CADWorker`.** A symbolication gap only; changing the helper's build would change a mirror input.
- **Pending Mac verification queue.** Its open rows ask for observations in Finder, VoiceOver and an installed build; the test run does not close them.
- **The YAML outline's limits.** Sequences of mappings (`- name: x`), anchors, block scalars, flow collections and multi-document files still fall back to source, which covers many real Kubernetes manifests. The store claim "YAML … as outlines" is true for plain nested mappings; decide in Phase 5 whether to qualify it. A sensitive key with a nested block (`auth:`, `credentials:`) conceals the rest of the file, so the outline ends there; bounding it safely needs a real YAML tokenizer and is later work.
- **Two known test issues** remain as recorded: right-to-left tab stops and the narrow-host line-number layout.

Later the same day:

- The owner merged the app and website pull requests, signed the Paid Apps Agreement (Active, with bank and tax forms Active) and declared trader status (In Review at Apple).
- The owner uploaded build 1.0.0 (2). Export and upload succeeded; the only warning is the missing `CADWorker` dSYM. App Store Connect showed the build as "Processing" ten minutes later; its result and its language list are still to be read.
- An email to Open Cascade asking whether the source-offer route is acceptable for the Mac App Store was drafted for the owner to send; R-2 waits for the answer.

2026-10-13:

- Open Cascade replied. The owner decided R-2: no STEP or IGES in 1.0. Build 2 stays an internal test build; build 3, built with `PREV_INCLUDE_CAD = NO`, is the submission build. Store copy, review notes, samples, the website and screenshot 07 follow (decision 028).

Next, in order:

1. Finish and verify the build without CAD, upload it as build 3 on instruction, install it through TestFlight and read which languages App Store Connect lists for it (expected: English only).
2. Retake screenshot 07 with a mesh model; re-paste the description and keywords in App Store Connect.
3. Phase 4 observations on the installed build, then Phase 5 trims the listing to what was seen, then Phase 6 and 7.

