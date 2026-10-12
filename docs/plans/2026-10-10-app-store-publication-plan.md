# App Store publication plan

Date: 2026-10-10 (Europe/Istanbul). Status: plan only. Nothing in this document has been executed: no file was deleted, no registration changed, no build made and nothing uploaded.

Scope, from the owner's request: remove the old bundle from this Mac and prepare this repository (`canburaks/spacepane`, moved from the sibling `prev` repository) for publication on the Mac App Store. The owner states that the App Store Connect app record and an App Store Connect API key now exist.

## How this plan was produced

Five read-only research agents (Sonnet 5.5) ran in parallel and the lead integrated their reports: a machine inventory, a signing and export audit, a current Apple requirements brief from primary sources, an extraction of open release gates from the repository's own records, and an audit of the move from `prev`. Their evidence is summarised here; each claim is marked as verified by command or file (V), inferred (I), or an owner statement (O).

Checked directly by the lead:

- The working tree of `spacepane` equals `prev` `master` at `3411445`, except for two tracked files the copy missed (see Phase 1). (V)
- `CADPeerRequirement.swift` accepts the Mac App Store leaf marker or the team organizational unit, and nothing else. A requirement of that shape was run with `codesign --verify -R` against a TestFlight-delivered app installed on this Mac (`/Applications/Agenda.app`, authority "TestFlight Beta Distribution"): it fails. The same requirement with `certificate leaf[field.1.2.840.113635.100.6.1.25.1] exists` added passes. (V)
- Another session changed this repository during the research: `Native/CADWorker/LICENSE` is new, and `SOURCE-OFFER.md`, `package_cad_source_offer.py` and `docs/dependencies/occt.md` were edited to record the OCCT route (publish the CAD helper's source as `canburaks/spacepane-cad-source`, contact `info@spacepane.com`). Those changes are uncommitted and are not part of this plan's edits. (V)

## Current state in one page

Ready:

- Identity is real and consistent: team `Z743N6D8DS`, bundle `org.webmeister.spacepane` with `.preview`, `.thumbnail` and `.cad-import`, App Group `Z743N6D8DS.org.webmeister.spacepane.shared`. They live in the git-ignored `Configuration/Local.xcconfig`. (V)
- Apple Distribution and Mac installer certificates are in the login keychain; Xcode created a store profile for the app on 2026-10-10. (V)
- `./script/build_and_run.sh --archive` and `--export` passed on this Mac on 2026-10-10 with Xcode 27.0; the exported package is signed for distribution and keeps the sandbox, group and helper entitlements. (V, `docs/validation/2026-10-10-testflight-dry-run.md`)
- Entitlements, Info.plist store keys, the icon set and four privacy manifests pass the repository's archive checker. (V)
- Apple sets no minimum Xcode or SDK for macOS uploads today; Xcode 27.0 and the hosted Xcode 26 are both acceptable. (V, Apple "Upload builds" and "Upcoming requirements", read 2026-10-10)
- The privacy and support pages are live on the Next.js site. (V)

Not ready:

| # | Gap | Kind |
|---|---|---|
| 1 | The CAD service refused a TestFlight-delivered preview extension: the peer requirement lacked the TestFlight leaf marker. Fixed in source and unit-tested on 2026-10-10; unproven on an installed SpacePane build. | Code defect, fixed in source |
| 2 | `.build/cad` in this checkout was copied from `prev`; its CMake caches name `/Users/cbs/Github/prev`, so the first archive here is expected to fail until the helper is rebuilt. | Build state (I) |
| 3 | No upload has ever run. Apple-side validation of the nested XPC service, of extensions without their own embedded profile and of the privacy manifests is unobserved. | Unproven |
| 4 | The store listing does not exist: no subtitle, description, keywords or screenshots in any language; the pricing model is not chosen. | Missing |
| 5 | No language has a review record. The owner's recorded rule is "only reviewed languages ship" (D22 (a)); `AGENTS.md` requires multilingual support. | Owner decision |
| 6 | The OCCT source repository is local only; the offer says "pending legal review". | Owner action |
| 7 | Finder evidence is thin: production identity observed for 3 of 76 formats, 0 thumbnails, never run on macOS 15. | Evidence |
| 8 | GitHub Actions is blocked on both repositories by an account billing failure; `canburaks/spacepane` has no secrets or variables. | Account |
| 9 | Development builds registered from build folders share the store bundle identifier and will compete with the store build for Finder routing. | Machine state, verified |
| 10 | Publishing research and three document edits exist only in `prev` worktrees and a stash. | Migration |
| 11 | The website and `brand.json` show `support@spacepane.com`; the owner's active address is `info@spacepane.com`. | Consistency (O) |

## Owner decisions

These steer the work. Each has a recommendation; none is assumed.

| # | Decision | Recommendation | Why |
|---|---|---|---|
| D-A | Keep or discard the current settings in `Z743N6D8DS.org.webmeister.spacepane.shared` when cleaning the Mac | Discard | A reviewer and every customer start clean; validation of the store build should too. Back the folder up first if any theme matters. |
| D-B | Languages in 1.0 | Ship English plus only the languages that get a recorded review before submission; amend `AGENTS.md:76` to allow that | It is the rule already on record (D22 (a)); zero languages are reviewed today. Store metadata cannot be offered in Kurmanji or Hausa in any case. |
| D-C | Pricing model, base storefront, price point, manual overrides | **Decided (owner, 2026-10-10):** a price of roughly USD 9.99 is set in App Store Connect with local pricing adopted. | App Store Connect holds the effective prices; the repository records no price table. The base storefront and any manual overrides were not stated. |
| D-D | STEP and IGES in 1.0 | Ship them, on the route already recorded today (public helper source repository), and get a lawyer's opinion before external testing or release | There is no build without CAD; cutting it is a project edit of several hours. The fallback stays available. |
| D-E | Build that is submitted | Archive on this Mac with Xcode 27.0 after confirming the Xcode build is a release build, not a beta or release candidate | The hosted Xcode 26 path has an unresolved Swift 6.3.3 optimizer crash and Actions is blocked. |
| D-F | API key | Use a Team key with the Admin role | Individual keys cannot use provisioning endpoints; forum reports say App Manager keys fail cloud signing. Role requirements beyond that are unverified. |
| D-G | App Group identifier | Keep the team-prefixed identifier | It is valid, needs no profile and avoids the macOS 15 container prompt. Apple recommends `group.` for new code; changing after release needs a migration review. |
| D-H | Extension-free text through `public.data` | Keep it and explain it in the review notes; drop the one format only if review objects | The fallback is one catalog entry. |
| D-I | Minimum macOS | Open. **Owner, 2026-10-10: no macOS 15 machine or virtual machine is available.** Either create a macOS 15 virtual machine on this Mac for the validation round, or raise the minimum to a version that was tested. | The app has never run on macOS 15; the only tested system is macOS 27.2. Shipping 15.0 as the minimum without a run is an unmeasured launch risk. |
| D-J | Store claims | Name only what has been observed in Finder on the store build | `AGENTS.md` forbids claiming routing that was not observed. |

Account steps only the owner can do (Account Holder): accept pending agreements, sign the Paid Apps Agreement, complete the tax form and banking, declare EU trader status with public contact details, enroll in the Small Business Program, resolve the GitHub billing failure, push `canburaks/spacepane-cad-source`, confirm the support mailbox answers.

## Phase 1 — Consolidate the repository

Goal: this repository holds everything worth keeping, and its documents say publication has started.

1. Commit or set aside the other session's uncommitted OCCT changes first, so later edits do not mix concerns.
2. Copy the two untracked research files from `/Users/cbs/.codex/worktrees/c18e/prev`: `docs/release/app-store-publishing-guide.md` and `docs/initial/08-app-store-publishing-research.md`. Correct the facts the requirements brief found outdated (privacy manifests now exist; no Xcode minimum for macOS; age rating; App Group guidance; key role).
3. Merge the `c18e` edits to `PLAN.md`, `CHANGELOGS.md` and `docs/release/app-store-submission.md` three ways, with base `3339304`. Do not copy the files: the `c18e` changelog is 1,067 lines behind.
4. Recover `docs/release/publishing-roadmap.md` from `git -C /Users/cbs/Github/prev show 'stash@{0}^3:docs/release/publishing-roadmap.md'` and reconcile it with `testflight.md`, or file it as history.
5. Restore the two tracked files the copy missed, from `prev` `master`: `.claude/launch.json` and `.codex/environments/environment.toml`.
6. Update the documents that contradict publication: `AGENTS.md:5` and `:120` (publication is now the active milestone, by owner request), `PLAN.md` header and M6, `docs/release/testflight.md:50` (`master` to `main`), `README.md` ("early development"), `AGENTS.md:15` (the Next.js site is deployed).
7. Decide the three unmerged branches in `prev` (`claude/design-system-website-3836bc`, `claude/notices-in-info-badge`, `claude/website-feature-showcase-409c38`). All are about 250 commits behind; port only what is still wanted.
8. Support address: change `web/src/data/brand.json:4`, `Website/support.html` and `Website/privacy.html` to `info@spacepane.com` (owner decision, 2026-10-10), update `PLAN.md:549` to match, rerun the website checks, and switch the Netlify site's linked repository to `canburaks/spacepane`.
9. Record each change in `CHANGELOGS.md`.

Exit: `git -C prev` holds nothing unique that is wanted; `./script/build_and_run.sh --check-static` passes.

## Phase 2 — Remove the old bundle from this Mac

Nothing is installed in `/Applications`. The "old bundle" is a set of development builds registered from build folders, plus data left by three generations of identifiers. (V)

Inventory:

| Category | Found |
|---|---|
| Extension registrations (`pluginkit -mAD`) | Preview and thumbnail, each registered twice: from the Debug build in `prev/.claude/worktrees/design-system-website-3836bc/.build/xcode` and from a deleted archive-intermediate path. The preview extension is user-enabled. |
| Running process | `PrevThumbnailExtension` from that worktree build |
| LaunchServices app records | 12, two of them pointing at deleted paths: Debug and archive builds in `spacepane/.build` and `prev/.build`, the worktree's Debug, archive and expanded export, `dist/PrevPrototype.app` in both repositories and in the Trash, and the retired `DerivedData/.../Prev.app` |
| Sandbox containers | 11 (three for `invalid.example.previewprototype`, four for `com.canburaksofyalioglu.filepreview`, four for `org.webmeister.spacepane`) |
| Group containers | 3 (one per identifier generation) |
| Application Scripts folders | 11, empty |
| Other | `~/Library/Application Support/PreviewPreferences`, Metal shader caches in the per-user cache directory, three `DerivedData/Prev-*` folders, three prototype provisioning profiles, one synthetic fixture folder in iCloud Drive |

Container contents and the Quick Look thumbnail cache could not be read: the terminal lacks Full Disk Access.

Runbook, in order. Steps 1 to 3 change registrations only and are reversible. Steps 4 to 7 delete files and are not.

1. Quit SpacePane if open. If D-A is "keep", copy `~/Library/Group Containers/Z743N6D8DS.org.webmeister.spacepane.shared` aside in Finder.
2. Stop the one extension process: `pkill -x PrevThumbnailExtension`. Do not kill Finder or Quick Look services.
3. Unregister, before deleting any folder:
   - `pluginkit -r "<path>"` for each of the four extension paths, then `pluginkit -mAD | grep -i webmeister` until empty.
   - `lsregister -u "<path>"` for each of the 12 app records, including the two deleted paths and the Trash copy.
4. Delete build products: `.build/xcode`, `.build/xcode-archive`, `.build/archive` in `spacepane`, in `prev` and in the `design-system-website-3836bc` worktree; that worktree's `.build/export` and `.build/export-expanded`; `competitor-feature-parity-bfbf59/.build/xcode-ext`; `dist/PrevPrototype.app` in both repositories. Keep the dry-run record in `docs/validation`; the exported package itself is reproducible.
5. Delete `~/Library/Developer/Xcode/DerivedData/Prev-*` (three folders) with Xcode closed.
6. Delete data of the two retired identifiers: their containers, group containers, Application Scripts folders, cache folders and `~/Library/Application Support/PreviewPreferences`. This needs Finder or a terminal with Full Disk Access.
7. Only if D-A is "discard": delete the four `org.webmeister.spacepane*` containers, the current group container, their Application Scripts folders and caches. This removes saved file-type choices, themes and profiles.
8. Optional: delete the three `invalid.example.previewprototype*` provisioning profiles. Keep the store profile and all certificates.
9. Verify: `pluginkit -mAD`, `lsregister -dump`, `mdfind` by bundle identifier and `pgrep` show nothing for the three identifier generations.

Not part of removal, per `AGENTS.md`: resetting the Quick Look thumbnail cache, `qlmanage -r`, restarting Finder, rebuilding the LaunchServices database, or changing the extension's enabled state with `pluginkit -e`. The enabled state is stored per identifier and will apply to the store build; that is acceptable for the owner's Mac but means this Mac cannot show the first-run enablement a customer sees.

Prevent recurrence: `script/build_and_run.sh:212-219` unregisters the archive intermediate from LaunchServices but not from PlugInKit. Add the matching `pluginkit -r` there (small script change, Phase 3).

Exit: after the TestFlight build is installed, `pluginkit -mAD | grep -i webmeister` shows exactly one preview and one thumbnail extension, both under `/Applications`.

## Phase 3 — Changes before the first upload

Required:

1. Done in source, 2026-10-10. `CADPeerRequirement`: accept the TestFlight leaf marker (`1.2.840.113635.100.6.1.25.1`) as a third branch, correct the comment, and extend its tests. Tests first, in their own commit. Alternative with a team-bound check: `xpc_connection_set_peer_team_identity_requirement` (macOS 14.4 and later), which means leaving `NSXPCConnection`; not recommended for 1.0.
2. Rebuild the CAD helper in this checkout: remove `.build/cad/kernel-arm64` and `.build/cad/worker-arm64`, run `python3 script/build_cad_worker.py --architecture arm64 --test`.
3. Language subset (if D-B is as recommended): a per-language review record in `tools/localization/languages.json`, a ship-list filter in `script/build_metadata.py`, pruned `InfoPlist.strings` outputs in `Prev.xcodeproj`, excluded `.lproj` resources in `Package.swift`, and the validators and tests that assume fourteen languages. This is the largest code item; it spans modules and the project file, so it needs a compiler.
4. About page: a way to open the bundled license notices and the source offer address (required while CAD ships). Bundle `ThirdPartyNotices/ColorSchemes/NOTICE.md` as well.
5. `ThirdPartyNotices/OCCT/NOTICE.txt` and `docs/dependencies/occt.md`: replace the "development build" and "unresolved gates" wording once the route is final.

Recommended:

6. `script/build_and_run.sh`: `pluginkit -r` for the archive intermediate.
7. Remove the hard-coded `DEVELOPMENT_TEAM` from three targets in `Prev.xcodeproj` so `Local.xcconfig` governs all four.
8. `CFBundleLocalizations` in the three Info.plists, listing the shipped languages.
9. Declare the file-timestamp reason on the CAD service's privacy manifest (the helper imports `stat`), and update the checker's expectation.
10. Move `~/Downloads/AuthKey_*.p8` to a private directory with mode 600. It must never enter the repository.

Every item runs `./script/build_and_run.sh --check` and the package tests on this Mac before it is committed.

## Phase 4 — First upload and internal TestFlight

1. Confirm in App Store Connect that the app record's bundle identifier is `org.webmeister.spacepane`.
2. Raise `CURRENT_PROJECT_VERSION` above 2 in `Configuration/Local.xcconfig` (build 2 was used by the dry run).
3. In the shell only, never in a file: `PREV_ASC_KEY_PATH`, `PREV_ASC_KEY_ID`, `PREV_ASC_ISSUER_ID`.
4. `./script/build_and_run.sh --check`, then `--archive`, `--export` (inspect the re-signed bundles), then `--upload`.
5. Record Apple's processing result and any validation message verbatim. This is the first observation of Apple-side validation.
6. Answer export compliance, create an internal group, install through TestFlight.

The upload is outward-facing and is run only on the owner's explicit instruction at that point.

The hosted `testflight` workflow is not on this path. Bring it up later: resolve billing, add the five secrets, dispatch `dry-run` first.

## Phase 5 — Validate the installed build

On the TestFlight install, on the current macOS and on macOS 15:

- `codesign -d -r-` on the installed preview extension; preview a STEP and an IGES file with the types enabled (closes decision 027 D27).
- Enable both extensions in System Settings; record the exact path shown on each macOS version for the review notes.
- No App Group consent prompt appears.
- Finder preview, the Quick Look panel and thumbnails for each format family; update `docs/validation/host-matrix.json`. This sets what the store copy may claim (D-J).
- VoiceOver and keyboard access in the companion and in a Finder-hosted preview.
- The "Open System Settings" link in the companion.
- Rows of `docs/validation/pending-mac-verification.md` that touch release-critical code: the dataless-file guard, the host session and timeouts, the privacy fixes, thumbnail admission.

A failure here returns to Phase 3 with a new build number.

## Phase 6 — Store listing and compliance

Can start in parallel with Phase 3; screenshots wait for the validated build.

- Text: name (30 characters), subtitle (30), promotional text (170), description (4,000, must name both extensions and say Apple silicon only), keywords (100 bytes), in English and each reviewed language. Store locales exist for every app language except Kurmanji and Hausa; Portuguese and Spanish need a regional choice.
- Screenshots: 2880×1800 or 2560×1600, real app and real Finder previews from the validated build, one to ten.
- App information: category Utilities with Developer Tools secondary, privacy policy URL `https://spacepane.com/privacy`, support URL `https://spacepane.com/support`, copyright, tax category "App Store software".
- App Privacy: "Data Not Collected".
- Age rating: answer the current questionnaire in full, including capabilities and social media; expected 4+.
- Export compliance: `ITSAppUsesNonExemptEncryption` is `NO`. Confirm first that no reader decrypts content (encrypted archives, certificate parsing is inspection only).
- Review notes: update `docs/release/app-store-submission.md` with how to enable the extensions, why `public.data` is declared, the `com.quicklookpro.*` alias list, the optional CAD previews and the source offer; attach the sample archive from `script/generate_host_fixtures.py`.
- Price and availability per D-C; manual release.
- Website: replace "Coming soon" with the store link at release; retire `Website/`.

## Phase 7 — Submit

Before submitting, recheck Apple's requirements pages again; the brief in this plan is dated 2026-10-10. Select the build, resolve any compliance prompt, add for review and submit, on the owner's explicit instruction. Record App Review feedback without presenting acceptance as certain. External TestFlight testing waits for the legal opinion on the OCCT route.

## Phase 8 — Retire `prev`

After Phase 1 is complete and Phase 2 has removed the registrations:

1. `git -C /Users/cbs/Github/prev bundle create ~/prev-all.bundle --all` as a backup of local-only branches and the stash.
2. Archive `canburaks/prev` on GitHub. Do not delete it: about twenty documents here cite its workflow runs and pull requests as evidence.
3. Remove the Codex worktrees `257f` and `c18e`, then the worktrees under `prev/.claude/worktrees` (39 GB), then the local clone (48 GB in total). Deleting the clone is irreversible for anything not in the bundle.

## Work split for execution

The lead owns the plan, the changelog, shared contracts, integration and every command that changes machine state or reaches Apple. Agents own disjoint files.

| Stream | Owns | Depends on |
|---|---|---|
| A. Repository consolidation | `docs/release/**`, `docs/initial/08-*`, `README.md`, `.claude/launch.json`, `.codex/**` | Other session's OCCT changes committed |
| B. CAD peer requirement | `Packages/PreviewCore/Sources/PreviewCADFormats/CADPeerRequirement.swift` and its tests | none |
| C. Language subset | `tools/localization/**`, `script/build_metadata.py`, localization validators and tests; the lead applies the `Prev.xcodeproj` and `Package.swift` parts | D-B |
| D. Notices and About | `Apps/PrevApp/**/AboutView.swift`, `ThirdPartyNotices/**`, `script/embed_cad_worker.py`, `script/stage_companion.py`, string additions file | D-D |
| E. Store listing drafts | a new `docs/release/store-listing/**` | D-B, D-C, D-J |
| F. Website | `web/**`, `Website/**` | support address |
| Lead | Phase 2 runbook, `Prev.xcodeproj`, `Configuration/**`, `script/build_and_run.sh`, `script/check_release_archive.py`, `PLAN.md`, `AGENTS.md`, `CHANGELOGS.md`, Phases 4, 5 and 7 | owner instructions |

Streams A, B, E and F can start at once. C and D wait for their decisions.

## What is not established

- Apple's server-side validation of this bundle layout has never run.
- The requirement string for store-delivered clients was checked against other vendors' installed apps, not against a SpacePane build.
- The API key's type and role are unknown; the role needed for cloud signing rests partly on unverified forum reports.
- Whether Xcode 27.0 (27A266a) is a release build is unverified.
- The legal sufficiency of the OCCT route is unreviewed.
- Whether the support mailbox exists and answers is unverified.
- Container contents on this Mac were not readable, so the settings at stake in D-A were not inspected.

## Execution status, 2026-10-10 evening

The owner instructed: discard all saved settings so the new build is the default, and carry out the remaining work. The price (roughly USD 9.99, local pricing) and the contact address (`info@spacepane.com`) were decided; no macOS 15 machine is available.

Done and verified:

- Phase 2, except the containers: process stopped, registrations removed, old builds and their data deleted. `pluginkit`, LaunchServices and Spotlight show nothing for the three identifier generations.
- Phase 1, steps 2 to 6 and 8 (repository side): documents ported, merged and corrected; missed files restored; `AGENTS.md`, `PLAN.md`, `README.md` and `testflight.md` updated; the website carries the new address.
- Phase 3, items 1, 2, 4, 6 and 10: the peer requirement, the rebuilt CAD helper, the About notice rows with the bundled color scheme notice, the archive-step cleanup and the key file location. An export read-back defect in `build_and_run.sh` was found and fixed.
- Phase 6, text drafts: `docs/release/store-listing/`. A second draft, `docs/release/app-store-listing.md`, came from another session and states that it supersedes the name, subtitle, keywords, promotional text and description of the first.
- Phase 8, step 1: `~/prev-all.bundle`.
- Evidence: `--check`, `--check-compiler`, `--test` (3,707 tests), `--archive` with the checker, and `--export` all pass in this checkout. See the changelog entries of the day.

Open, waiting for the owner:

- Delete the eleven sandbox containers and three group containers in Finder (macOS refused the terminal), or grant Full Disk Access.
- The upload needs the issuer ID and key ID in the shell and an explicit instruction. The key file is in `~/.appstoreconnect/private_keys/`.
- Decisions D-B (languages), D-I (macOS 15: virtual machine, raise the minimum, or accept the risk) and whether to use internal TestFlight before review.
- Deploy the website and switch its linked repository; confirm the mailbox answers.
- Commit the working tree. Nothing from this work is committed.
- Account steps: agreements, tax and banking, trader status, GitHub billing.

Deferred by the lead, with reasons:

- Phase 3 item 3 (language subset): it is the owner's decision D-B.
- Items 7 to 9 (team setting in the project file, `CFBundleLocalizations`, the CAD service privacy manifest): hygiene only, each touches release-critical configuration, and item 8 depends on D-B. The service manifest's current content is a recorded decision (027, Q-45).
- `ThirdPartyNotices/OCCT/NOTICE.txt` wording and regenerating `spacepane-cad-source`: another session owns the OCCT legal files; a proposed text exists in that stream's report.
- Phases 4, 5 and 7: they need the upload.
- Phase 8, steps 2 and 3: archiving `canburaks/prev` and deleting the clone are irreversible for the owner's history and were not instructed.
