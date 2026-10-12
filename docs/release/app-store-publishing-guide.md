# SpacePane App Store Publishing Guide

Prepared 2026-10-07 (Europe/Istanbul). For the first native macOS release and subsequent updates.

**Corrections of 2026-10-10.** Publication preparation started on 2026-10-10, after this guide was written. Seven statements were checked against Apple's pages, the repository and this Mac and are corrected where they appear below; each carries a "Corrected 2026-10-10" label. In short: four privacy manifests now exist; Apple sets no minimum Xcode or SDK for macOS uploads; Apple now recommends `group.` App Group identifiers for new code, but the team-prefixed form stays valid and stays here; the age-rating questionnaire was replaced in 2026; App Store Connect offers 50 metadata locales, without Kurmanji or Hausa; the API key should be a Team key with the Admin role; and a TestFlight build is signed with the TestFlight certificate, not the Mac App Store one. The [publication plan](../plans/2026-10-10-app-store-publication-plan.md) sequences the remaining work.

SpacePane already has an App ID, a chosen name and pricing plans, according to the owner. Since 2026-10-10 the owner also reports that the App Store Connect app record and an App Store Connect API key exist, and that a price of roughly USD 9.99 is set in App Store Connect with local pricing adopted (owner statements; Apple's account was not inspected). Start from those existing records. The remaining work is to make the exact distribution build reliable, reconcile its public claims with observed Finder behavior, complete App Store Connect disclosures, and give App Review a reproducible way to test it.

**The repository does not yet establish submission readiness.** The highest-priority gates are the CAD dependency's distribution license, CAD client authentication after Apple re-signing, current-build Finder validation on macOS 15 and the current stable OS, reviewed shipping languages, and Organizer/App Store Connect distribution validation. A successful local archive closes none of those by itself.

Active support contact: **info@spacepane.com**, confirmed by the owner. The guide does not create identifiers, change prices, submit a build or publish the app. Apple account settings were not inspected when this guide was written. Update 2026-10-12: build 1.0.0 (1) was uploaded on 2026-10-10 and is processed and "Ready to Submit", with zero installs; it is not attached to the version and will not be submitted, and build 2 is being prepared. Nothing has been submitted for review. The account state read on 2026-10-12 is in [the listing record](app-store-listing.md#what-app-store-connect-holds) ([dry-run record](../validation/2026-10-10-testflight-dry-run.md)). Use the [historical research](../initial/08-app-store-publishing-research.md) for reported failures and outcomes, and the [submission worksheet](app-store-submission.md) for review notes.

## Contents

1. [Starting position and release priorities](#1-starting-position-and-release-priorities)
2. [Verify the existing account and commercial setup](#2-verify-the-existing-account-and-commercial-setup)
3. [Freeze the release scope and claims](#3-freeze-the-release-scope-and-claims)
4. [Prepare signing, sandboxing and nested code](#4-prepare-signing-sandboxing-and-nested-code)
5. [Resolve the CAD distribution gates](#5-resolve-the-cad-distribution-gates)
6. [Build the release candidate and test its delivery](#6-build-the-release-candidate-and-test-its-delivery)
7. [Prepare privacy, age rating and compliance answers](#7-prepare-privacy-age-rating-and-compliance-answers)
8. [Prepare the product page](#8-prepare-the-product-page)
9. [Give App Review a reproducible test](#9-give-app-review-a-reproducible-test)
10. [Submit, diagnose and respond](#10-submit-diagnose-and-respond)
11. [Release and maintain the app](#11-release-and-maintain-the-app)
12. [Final go or no-go checklist](#12-final-go-or-no-go-checklist)

## 1. Starting position and release priorities

The following separates owner confirmation, checked-in configuration and older validation evidence. It is a release planning assessment, not an App Review decision.

| Area | Evidence and current position | Next action |
| --- | --- | --- |
| App ID, name, pricing plans | Owner says these exist. | Reconcile existing records with the archive; do not recreate them. |
| Production identity | PLAN M6 records `org.webmeister.spacepane` and App Group `Z743N6D8DS.org.webmeister.spacepane.shared`, adopted on October 6. Committed Base.xcconfig deliberately retains compile-only placeholders; ignored local configuration supplies signing values. | Verify effective Release build settings and the existing Apple records, including nested targets. |
| Product baseline | macOS 15+, currently `ARCHS = arm64`, version 1.0.0/build 1 in Base.xcconfig. | Advertise Apple silicon only unless a separately validated universal build is approved. Increment the upload build number. |
| File coverage | The integrated catalog contains 76 logical types and 309 suffixes. Earlier 22-format Finder tests are narrower than this catalog. | Establish a current-build, per-format claim matrix. Do not market 76 verified Finder integrations from parser counts. |
| CAD | Opt-in IGES/STEP geometry exists; licensing and broader platform gates remain open. | Resolve the license route and test Apple-delivered XPC authentication before advertising CAD. |
| Languages | Fourteen language resource sets exist; native-speaker and installed-host validation remain open. Decision 2026-10-12 (owner rule: only reviewed languages ship): no language has a recorded review, so build 2 ships English only and the other 13 stay in the repository as drafts. | Approve an explicit shipping-language list and make resources, metadata and advertising agree. |
| Website | On October 7, `/support.html` and `/privacy.html` redirected to `/support` and `/privacy` and returned HTTP 200. Both rendered pages still displayed `support@spacepane.com`. *Superseded 2026-10-12:* the support, privacy and open-source pages are live and show `info@spacepane.com` everywhere; the domain has MX, SPF and DMARC records. | Test mail delivery: whether the mailbox answers is unconfirmed. A working page does not prove mailbox delivery. |
| Upload readiness | An earlier archive passed local checks. On 2026-10-10 `--archive` and `--export` passed with the production identities and Xcode 27.0 ([dry-run record](../validation/2026-10-10-testflight-dry-run.md)). *Updated 2026-10-12:* build 1.0.0 (1) was uploaded on 2026-10-10 and App Store Connect processed it; the processing result was not recorded verbatim in the repository. It is not attached to the version and will not be submitted. | Repeat on build 2 and retain distribution logs and Apple's messages verbatim. |

Sources of repository truth: [PLAN](../../PLAN.md), [change history](../../CHANGELOGS.md), [base configuration](../../Configuration/Base.xcconfig), [branding configuration](../../Configuration/Branding.xcconfig), [parity validation](../validation/parity-program-2026-10-05.md), [earlier Finder matrix](../validation/finder-matrix-2026-10-04.md), [CAD audit](../dependencies/occt.md). The top of PLAN still describes 24 formats; its later parity section and the catalog supersede that historical count. Old checkboxes are not evidence about a new binary.

### Recommended order

1. Resolve release scope and CAD licensing; inspect the CAD authentication design.
2. Produce a distribution candidate, test Apple-delivered CAD authentication, and close minimum-OS, Finder, privacy and accessibility defects.
3. Review shipping translations and correct public support/privacy information.
4. Finish product-page assets and factual disclosures against that candidate.
5. Run TestFlight, prepare review fixtures, submit for review, then release deliberately.

Do not spend the last release day discovering that a dependency cannot be distributed or the main feature fails under Apple's signature. These checks precede screenshot polish.

## 2. Verify the existing account and commercial setup

Open the existing macOS app record in App Store Connect. An explicit App ID in Certificates, Identifiers & Profiles and an App Store Connect app record serve different purposes; verify that both point to the same main bundle ID. Preserve the numeric Apple app ID, SKU and signing identity in the release record. Extension and XPC identifiers belong to the same distributed app, not separate store listings. [Apple: add an app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)

### Account checklist

- Confirm Developer Program membership and access for the person who will upload, edit metadata and submit.
- Create the App Store Connect API key as a **Team key with the Admin role**. Corrected 2026-10-10: an Individual key cannot use the provisioning endpoints, and forum reports (unverified) say a key with the App Manager role fails cloud signing. Keep the `.p8` file in a private directory with mode 600, never in the repository.
- Ask the Account Holder to resolve any pending agreements. For paid distribution, check that the Paid Apps Agreement and required banking/tax setup are active; a price schedule alone does not establish this.
- Review storefront-specific compliance notices in the account. Do not infer the legal seller's country, tax status or trader status from this computer's language or timezone.
- Declare trader status even if not distributing in the EU. If distributing in the EU as a trader, complete the required public-contact verification. Trader contact details are a separate public disclosure from the support URL and the private App Review contact. Supply accurate information and complete verification; a support email alone does not finish it.

[Apple: agreements](https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/), [banking](https://developer.apple.com/help/app-store-connect/manage-banking-information/enter-banking-information/), [tax information](https://developer.apple.com/help/app-store-connect/manage-tax-information/provide-tax-information/), [EU trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/).

### Keep the existing pricing plan

*Update 2026-10-10 (owner statement):* a price of roughly USD 9.99 is set in App Store Connect with local pricing adopted. The base storefront and any manual overrides were not stated, and App Store Connect remains the only place that holds effective prices.

SpacePane's recorded country-specific pricing requirement means regional prices, not subscriptions or feature tiers. Confirm the existing base country, effective date, selected price points, manually overridden countries and storefront availability. Record the agreed policy and a dated verification, while leaving effective prices in App Store Connect. Automatic equalization and manual overrides behave differently; recheck the countries you intentionally customized. [Apple: set a price](https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price/)

The current app has no in-app purchase implementation. If the existing plan is paid upfront, continue with it; StoreKit is not needed merely to charge a download price. If the account instead describes a free download with a paid unlock, that is a material product/implementation mismatch to resolve before submission. Do not silently introduce an unlock, external activation key or subscription into this guide's workflow. [Repository pricing boundary](../../PLAN.md#country-specific-pricing)

## 3. Freeze the release scope and claims

Create a release record tied to a commit, marketing version, build number and archive. For every advertised family, record the parser capability, declared UTType, resolved UTType of the fixture, observed provider, Space-bar result, Finder preview-pane result, thumbnail result, OS, architecture and restrictions. Keep screenshots or a short recording with synthetic inputs.

| Proposed claim | Evidence required for SpacePane |
| --- | --- |
| Finder previews for a format | Actual invocation of SpacePane on the installed distribution candidate, with a recorded resolved type and surface. |
| Content thumbnails | The real thumbnail extension's result and privacy behavior; a cached system thumbnail is insufficient. |
| Works when the app is closed | Quit the companion normally, request fresh previews, confirm correct settings and provider. |
| Supports macOS 15 | Run the exact candidate on macOS 15; the deployment target is insufficient. |
| Supports a language | Reviewed copy, layout, keyboard/VoiceOver checks and effective language behavior in the companion and both extensions. |
| Fast or memory efficient | Recorded Release measurements including helper processes and Finder presentation, with cold/warm samples. |
| Keeps secrets private | Tested concealment in every representation and clear limits. Another provider's output is outside SpacePane's control. |

The platform selects the Quick Look provider. An exact content-type declaration is not a priority guarantee; declaring a parent type does not establish handling of all descendants. Preserve SpacePane's single, exact `public.data` preview-only exception for extensionless text; it is not a universal fallback and does not cover executable-bit files. App Store acceptability for that declaration remains a tracked review question, not a known prohibition. [Apple: Quick Look session](https://developer.apple.com/videos/play/wwdc2019/719/), [extensionless-file decision](../decisions/011-extensionless-files.md).

Use careful customer wording: “conceals likely secrets in SpacePane previews” is supportable when tested; “prevents secrets ever appearing in Finder” is not. Content thumbnails may persist in macOS's cache. Embedded document images and CAD geometry can reveal information that text pattern matching cannot conceal. Safety findings are indicators, not malware certification or an engineering guarantee.

The companion's normal interface stays General, File Types, Theme and About in one window. Developer Mode remains off by default and reveals Try Preview. Reviewers should be able to understand the product through normal setup, controls and Theme samples; the development tool is a supplemental diagnostic, not a substitute for working Finder integration. [Sidebar decision](../decisions/010-companion-sidebar-redesign.md)

## 4. Prepare signing, sandboxing and nested code

Use the Mac App Store distribution workflow in Xcode. Developer ID signing, notarization and stapling are a separate direct-download channel; they are not substitutes for App Store upload validation. Confirm the currently accepted Xcode/toolchain on the submission date, without applying an iOS-only SDK deadline to this native Mac app.

*Corrected 2026-10-10:* Apple sets no minimum Xcode or SDK version for macOS uploads today. The "Upload builds" table lists the macOS app as "Built using Xcode 6 or later", so the Xcode 27.0 used on this Mac and the Xcode 26 on the hosted runner are both acceptable. Read on 2026-10-10 at [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/) and [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/); recheck both before submitting. [Apple: distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases), [upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)

### Preserve the existing identity

Verify the effective main ID, preview ID, thumbnail ID, CAD service ID and group from build settings and the signed bundle. Do not replace the TEAMID-prefixed group with an invented `group.*` value: macOS has its own App Group provisioning conventions, and a change can strand preferences. Ensure the relevant profiles authorize the actual group.

*Corrected 2026-10-10:* since 2025-02-21 Apple's guidance is to use `group.`-prefixed identifiers for new code, which also works on macOS. The team-prefixed form this project uses (`Z743N6D8DS.org.webmeister.spacepane.shared`) remains valid, needs no provisioning profile entry and avoids the macOS 15 prompt about accessing another app's container ([Apple DTS](https://developer.apple.com/forums/thread/721701)). The project keeps the team-prefixed form; changing it after release would need a separate compatibility and migration review. [Apple: configuring App Groups](https://developer.apple.com/documentation/xcode/configuring-app-groups), [Apple DTS: App Groups on macOS](https://developer.apple.com/forums/thread/721701)

### Inspect each executable's role

| Component | Expected role and release check |
| --- | --- |
| Companion | Sandboxed; shared preferences writer; user-selected read/write grant supports explicit theme export. Actual preview source reads remain read-only. |
| Preview extension | Sandboxed; App Group reader; owns host-granted file lifetime; must not require companion to run. |
| Thumbnail extension | Sandboxed; stricter budgets and safe thumbnail policy; no CAD importer or interactive/audio renderer. |
| CAD XPC service | Independently sandboxed, embedded in the preview extension; authenticated clients and connection-owned cancellation. |
| Two CADWorker executables | One in the companion and one in the service; inherited sandbox. Current policy permits exactly sandbox and inherit entitlements. Each signing identifier is its owning bundle ID plus `.CADWorker`. |

App Sandbox for a child tool and for an XPC service are different configurations. Do not copy the companion's entire entitlement set onto an inherited helper or remove sandboxing to solve an upload error. Inspect the final signed entitlements, not only source `.entitlements` files. [Apple: embedding a command-line tool](https://developer.apple.com/documentation/xcode/embedding-a-helper-tool-in-a-sandboxed-app), [resolved DTS case](https://developer.apple.com/forums/thread/679940).

SpacePane's local checker verifies architectures, signatures, sandbox/network/temporary-exception policy, notices, metadata and helper identifiers. It does not evaluate the service's client-authentication requirement against Apple's delivered signature, nor prove Finder behavior. `get-task-allow` is noted in a development archive; verify its absence after distribution signing. [Archive checker](../../script/check_release_archive.py)

## 5. Resolve the CAD distribution gates

### License clearance before distribution

The pinned OCCT 7.9.3 library is statically linked into the worker. The repository explicitly leaves release blocked on an approved route for corresponding source, modified build manifests, scripts and applicable relinking materials, or a separately approved licensing route. Local `.o` files and copied notices do not close the distribution obligation. The upstream header exception is not a blanket static-linking exemption. [Repository audit](../dependencies/occt.md), [pinned upstream exception](https://github.com/Open-Cascade-SAS/OCCT/blob/a016080bf6738d6aeae020badee4e888ad1540a5/OCCT_LGPL_EXCEPTION.txt)

Before distributing a beta or production binary containing this dependency, have the chosen licensing route reviewed for the actual Store channel, retain the required materials and document how recipients obtain them. Apple accepting a binary does not settle third-party license compliance. Turning CAD off by default does not remove a library already shipped inside the bundle. If clearance requires a release-scope change, get that product decision explicitly and remove the dependency from the artifact as well as the claim; do not treat metadata-only CAD as satisfying the requested 3D feature.

A CAD-free artifact would require implementation and build/validation changes: the current archive workflow always builds CAD, and the checker expects the service and two workers. It is not an available release switch.

### Verify client authentication after Apple re-signing

Historical description, before 2026-10-06: the service constructed a requirement with an unconditional `certificate leaf[subject.OU] = <developer Team ID>` condition in [Native/CADImportService/main.swift](../../Native/CADImportService/main.swift). Apple's signing documentation distinguishes Store signing from Developer ID signing and shows separate branches in compatible requirements. This creates a **credible distribution risk**: a development or exported build may work while an Apple-delivered preview client fails the service's requirement. It is not a confirmed SpacePane Store failure. [Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)

*Corrected 2026-10-10:* the risk is real for TestFlight, and the cause is more specific than this section assumed. The code (`Packages/PreviewCore/Sources/PreviewCADFormats/CADPeerRequirement.swift`) accepted two branches until 2026-10-10: the Mac App Store leaf marker (OID `1.2.840.113635.100.6.1.9`) or the team organizational unit. It now has three, with the TestFlight marker (`1.2.840.113635.100.6.1.25.1`) added. A TestFlight-delivered app is not signed with the Mac App Store certificate. Measured on 2026-10-10 on this Mac, the leaf certificate of an app delivered by TestFlight is "TestFlight Beta Distribution" with OID `1.2.840.113635.100.6.1.25.1` and without `1.2.840.113635.100.6.1.9`. The two-branch requirement fails `codesign --verify -R` against it, and the same requirement with the TestFlight branch added passes. The three-branch change is complete in source and unit-tested, and the generated text also passes against four Mac App Store-delivered apps and a Developer ID app with the right team, and fails for a wrong team or identifier (stream B, 2026-10-10). None of this was measured on a SpacePane build, and no Xcode build with the change exists yet, so it is unproven until an installed TestFlight build proves the TestFlight form and a store-delivered build proves the Mac App Store form (decision 027, D27). The TestFlight leaf's organizational unit reads the literal `TESTFLIGHT`, never a team.

On an isolated test installation, inspect the delivered preview extension's designated requirement and evaluate the exact requirement from the service against it. For the identifiers recorded in PLAN, the read-only diagnostic is the exact three-branch text the service now generates:

```sh
codesign -d -r- "/path/to/SpacePane.app/Contents/PlugIns/PrevPreviewExtension.appex"
codesign --verify -vv \
  -R='anchor apple generic and identifier "org.webmeister.spacepane.preview" and (certificate leaf[field.1.2.840.113635.100.6.1.9] exists or certificate leaf[field.1.2.840.113635.100.6.1.25.1] exists or certificate leaf[subject.OU] = "Z743N6D8DS")' \
  "/path/to/SpacePane.app/Contents/PlugIns/PrevPreviewExtension.appex"
```

The older team-OU-only form of the requirement fails on store-delivered builds by design, because their leaf certificates carry no team (the TestFlight leaf reads `TESTFLIGHT`); do not use it as the acceptance check. Replace the path with the actual delivered installation and confirm identifiers from the bundle first. A failure requires a reviewed authentication fix that still restricts clients to the intended extension; do not remove authentication or accept arbitrary Apple-signed code. Then test real STEP/IGES requests through Finder, including close/cancel, with the companion stopped. TestFlight is a necessary distribution test, and the first Store-delivered build needs its own smoke test as well.

## 6. Build the release candidate and test its delivery

### Preserve reproducible evidence

Record the commit, working-tree state, Xcode/SDK versions, OS/hardware, selected architecture, effective identifiers, version/build and dependency revision. Archive the final source state, signed archive, dSYMs, distribution logs, review assets and test matrix. Keep credentials and private customer files out of that package.

Before each new or replacement upload, increment `CURRENT_PROJECT_VERSION`, even when `MARKETING_VERSION` remains 1.0.0. Keep the app, extensions and XPC bundle versions consistent and record any Organizer-managed override.

The repository provides these entrypoints:

```sh
./script/build_and_run.sh --check
./script/build_and_run.sh --check-compiler
./script/build_and_run.sh --test
./script/build_and_run.sh --test-cad
./script/build_and_run.sh --archive
```

Run CAD checks when CAD is in scope. These commands are release instructions, not tests executed during this research. `--archive` builds the arm64 CAD worker, creates `.build/archive/Release.xcarchive`, and runs the local checker. It replaces that archive path, so preserve a previous candidate before rerunning it. The script also cleans up its own intermediate registered build; do not add broad Finder resets or shared-cache clearing. [Build entrypoint](../../script/build_and_run.sh)

Open the archive in Xcode Organizer, run **Validate App**, then use the App Store Connect distribution/upload path. Review the signing and provisioning summary for every nested component. Keep any validation error verbatim in the release issue before changing settings. Upload success means transport succeeded; wait for processing and any compliance messages before selecting the build. [Apple: upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)

### TestFlight and installed-host matrix

Owner decision of 2026-10-12: internal TestFlight testing only, with no external testers and no public link. The internal group "Internal" exists. (The earlier text here planned external testers after beta review; that plan is withdrawn.) Give testers a focused script and synthetic fixtures. A beta review is not production approval, and a TestFlight pass does not establish the final Store receipt/signature path. [Apple: TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

| Test | Acceptance evidence |
| --- | --- |
| Fresh install and first launch | No development configuration, missing resource or unexpected authorization dependency. System Settings instructions lead to the available Quick Look extensions. |
| Normal companion use | Four normal sidebar destinations; Theme samples load; settings save; close the window and reopen the same singleton via normal app/menu behavior. |
| Finder with companion stopped | Space-bar and preview-pane behavior attributed to this build, including a fresh process after normal closure. |
| Type controls | Disabled formats stay disabled across relaunch and do not leak through a generic fallback. No promise that another provider will take over. |
| Thumbnail privacy | Current content/generic choice verified with synthetic sensitive and nonsensitive inputs; cached old thumbnails distinguished from new output. |
| File access | Open/drop grants, unavailable cloud bytes, denied access, symlinks and SQLite sidecars handled without source writes or broad permission workarounds. |
| CAD | Both default-off switches remain off initially; opt-in geometry works under delivered signing; cancellation ends request-owned work. |
| Minimum and current OS | macOS 15 plus the current supported stable OS on Apple silicon; record each OS version and actual build. |
| Language and accessibility | Selected release languages in companion and Finder; keyboard-only operation, VoiceOver, contrast and content enlargement tested. |
| Upgrade | Saved type choices, themes and preferences survive an update; no reset to enabled content or new group container. |
| Provider coexistence | Test on a normal machine with competing providers and record observed selection without overrides. |

Keep one clean test environment without stale SpacePane development copies, and a separate coexistence environment. Do not “repair” routing evidence by killing Finder, changing shared extension preferences through scripts, or resetting the system's Quick Look cache. Capture the environment and investigate the actual registration/type mismatch.

Avoid an **Internal Only** TestFlight upload for a candidate intended for production review; Apple restricts those builds to internal groups. External testing is not planned (owner decision, 2026-10-12). Build testing expires after 90 days; plan enough time for correction and another beta rather than relying on an old build indefinitely. [Apple: external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers), [TestFlight limits](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

## 7. Prepare privacy, age rating and compliance answers

### App Privacy and the public policy

“Data Not Collected” is a candidate answer for SpacePane's local architecture, subject to checking the actual binary, extensions, helpers and third-party dependencies. Apple distinguishes on-device processing from off-device collection. Its optional-disclosure rules for support/feedback require multiple conditions; they are not a general exemption for anything called diagnostics. [Apple: App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/)

Audit local file processing, preferences, crash/usage reporting, network behavior, clipboard actions and support flows. Record any dependency that changes these answers. Absence of a network entitlement is useful evidence, not a substitute for the audit. Distinguish app behavior from the website's hosting and from a person voluntarily emailing support.

Use the live [privacy policy](https://spacepane.com/privacy), correct its contact to **info@spacepane.com**, and confirm it matches the submitted build. Explain heuristic concealment, content-thumbnail caching and voluntary support-email handling. Avoid absolute promises that the product cannot enforce, including erasure of system-generated caches.

In App Store Connect → **App Privacy**, complete answers, **Save**, inspect the product-page preview, then **Publish** and confirm accuracy. Leaving saved draft answers is not the completed step. [Apple: manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)

### Privacy manifests and required-reason APIs

*Corrected 2026-10-10:* the repository now has four privacy manifests (`PrivacyInfo.xcprivacy`): in the app, in both extensions and in the CAD service. The archive checker requires all four and checks Apple's reason codes for the file-timestamp, system-uptime and user-defaults categories the code uses. The paragraph below describes the 2026-10-07 position, when none had been found; what remains open is how Apple's validation treats them, which only an upload shows.

A privacy label and `PrivacyInfo.xcprivacy` have different jobs. The repository search on 2026-10-07 found no privacy manifest; it did find UserDefaults and system-uptime use. Apple's current required-reason article lists iOS, iPadOS, tvOS, visionOS and watchOS, omitting native macOS. Therefore, absence of that file is **not automatically a demonstrated native-Mac rejection**. Recheck platform scope and the listed-SDK rules for the final payload. If a Mac manifest is included, its documented bundle location is `Contents/Resources/PrivacyInfo.xcprivacy`. [Apple: required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api), [manifest packaging](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk), [listed SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/)

Record applicability rather than adding guessed reason codes. A generated privacy report is not a complete dependency audit. Inspect upload processing messages and the actual resources in each owning bundle. Do not transplant mobile-only missing-manifest incidents into a blanket macOS rule.

### Export compliance

The app currently declares `ITSAppUsesNonExemptEncryption = NO`. Reassess that against the shipped certificate/signature inspection functionality, operating-system cryptography and dependencies. The key means no **non-exempt** encryption; it does not mean the program has no cryptographic API calls. Complete the App Store Connect determination and retain its basis. If documentation is required, resolve it for the build before beta/review. Local-only operation does not answer the encryption question. [Apple: export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)

### Age rating

*Corrected 2026-10-10:* Apple replaced the age-rating questionnaire in 2026. It now also asks about in-app controls, capabilities and social media, and answers are required for new submissions since September 2026. For SpacePane every answer is expected to be "None" or "No", for an expected rating of 4+; the calculated result is Apple's, not ours to promise.

Complete the current **App Information → Age Ratings** questionnaire using the actual capabilities, then inspect the calculated ratings. Do not reuse the previous worksheet's instruction to answer “None” everywhere. Apple asks about capabilities and controls as well as content. A utility displaying local files is not automatically a public content-sharing service or unrestricted browser, and secret concealment is not automatically a parental control. Document the rationale for any ambiguous answer and resolve it with Apple; do not promise a specific rating in advance. [Apple: age-rating questionnaire](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating)

### Other questions shown in the account

If **Digital Goods and Services** appears, answer for the actual payment/access model. Apple says no action is needed when it is absent. Its definition includes features and experiences, so no IAP is insufficient grounds for an automatic “No”; EU selections are locked for 12 months after submission. [Apple: Digital Goods and Services questionnaire](https://developer.apple.com/help/app-store-connect/manage-app-information/complete-the-digital-goods-and-services-questionnaire)

Complete other territory or account requests only where applicable. Keep app age rating, seller/trader status, tax category, export compliance and dependency licensing separate; success in one does not answer the others.

## 8. Prepare the product page

### Field worksheet

| Field | SpacePane entry or preparation |
| --- | --- |
| Name | Preserve the existing SpacePane record; do not add search keywords to the name. |
| Subtitle | Draft for the actual positioning; for example, “Local previews for your files” (29 characters). |
| Primary category | Utilities, consistent with `public.app-category.utilities` in the bundle. |
| Secondary category | Developer Tools is a reasonable option if it matches the final audience. |
| Support URL | `https://spacepane.com/support`; it must show the active info@spacepane.com contact. |
| Privacy policy URL | `https://spacepane.com/privacy`; keep legacy `.html` redirects working for current About links. |
| Marketing URL | `https://spacepane.com`. |
| Copyright | Match the approved rights-holder value in Branding.xcconfig. |
| Version/build | Match the selected uploaded build, not an old worksheet. |
| Review contact | A reachable person, international phone number with `+` and country code, and email Apple can use. Use info@spacepane.com for email if monitored; this is not the entire contact record. |
| Content Rights | Assess actual third-party content accessed or bundled; verify rights for samples, assets and screenshot/review material rather than choosing a blanket answer. |
| Login requirement | No sign-in, if the shipping app retains its accountless design. |
| Languages | Reviewed store translations and actual shipped app resources, checked separately. |

Apple limits the name to 30 characters and subtitle to 30; description to 4,000 characters, keywords to 100 bytes and review Notes to 4,000 bytes. Check bytes for multilingual entries. Do not rename identifiers to match metadata edits. [Apple: app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information), [platform version fields](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)

### Description structure

Lead with what the user gets: SpacePane adds Quick Look preview and thumbnail extensions for supported files on the Mac. Follow with the families actually verified, useful controls, local processing and customization. Finish with setup and meaningful restrictions: Apple silicon/macOS 15+, system-selected providers, bounded format support and default-off CAD if included.

Keep the two extension roles explicit. Apple requires accurate extension disclosure and useful containing-app functionality where possible. Mac Store rules also require sandboxing and self-contained Xcode packaging, and prohibit several practices such as downloaded feature code, root escalation and independent update mechanisms. SpacePane's normal settings/sample interface and embedded dependencies should demonstrate compliance without a separate installer. [Apple: guidelines 2.4.5 and 4.4](https://developer.apple.com/app-store/review/guidelines/)

Do not list every suffix merely to fill keyword space. Prefer customer terms for the families that actually ship. Avoid competitor names, rankings, unmeasured performance numbers, “all files,” “always replaces Finder previews,” or blanket security guarantees. Ensure the website and store describe the same release scope.

### Screenshots and optional video

Mac screenshots must be 16:10, using 1280×800, 1440×900, 2560×1600 or 2880×1800 pixels. Apple allows 1–10 screenshots in JPEG/JPG/PNG; a preview video is optional. [Apple: screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications), [asset upload](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots)

Recommended sequence:

1. Real Finder preview of a clear, verified structured-data sample.
2. Selectable safe source with an unmistakably synthetic concealed value.
3. File Types controls showing individual choices.
4. Theme live preview with legible typography and appearance options.
5. Another validated family, such as an archive listing or table.
6. Optional CAD geometry only after licensing and delivered-build validation.

Capture the submitted build. A website simulation is not a screenshot of the native Finder extension. Use synthetic files and neutral paths; exclude the supplied private CAD model, personal folders, genuine tokens, customer records and unlicensed documents. Check readability at actual store display size. Capture reviewed localizations where supplied; store-localization choices and macOS resource tags are not necessarily a one-to-one mapping.

*Corrected 2026-10-10:* since 2026-03-31 App Store Connect offers 50 metadata locales ([App Store localizations](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations)). Every app language except Kurmanji and Hausa has a store locale; those two can be shipped in the app but cannot have a store listing. Portuguese and Spanish each need a regional choice.

### Accessibility claims

Apple currently describes Accessibility Nutrition Labels as voluntary and supplies feature/device-specific criteria; the Larger Text label is not supported for Mac. Add only claims established by testing common tasks. SpacePane's test suite and native controls do not establish VoiceOver support in remote Finder hosts by themselves. [Apple: accessibility labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels)

## 9. Give App Review a reproducible test

The reviewer should be able to install the app, enable its extensions, open a supplied file and recognize SpacePane's result without special knowledge. Prepare:

- A small ZIP of synthetic fixtures with filenames and expected outcomes in a README.
- A known-routing text/structured sample, an archive/table sample, and a harmless malformed/oversized example if it explains a relevant fallback.
- STEP/IGES samples only if CAD ships and the attachment rights are clear.
- Concise setup steps checked on macOS 15 and the current stable OS.
- A short optional recording showing the exact build and Finder steps.
- Reachable App Review contact details and an explanation of the accountless purchase model.

`python3 script/generate_host_fixtures.py` creates a fresh synthetic fixture directory. Inspect its current output and verify the selected files against the release build before making the ZIP. A generated fixture proves neither all-format coverage nor successful Finder routing. Do not attach the private CAD acceptance model or developer machine logs containing source content.

Use the [updated Notes template](app-store-submission.md#notes-for-app-review) and replace every bracketed field. If a fixture routes to another provider during your test, choose a verified representative and record the limitation; do not tell the reviewer to delete competing software or run terminal repairs.

Explain that macOS hosts preview/thumbnail extensions on demand, including while the companion is closed. CAD imports use an embedded helper and do not require downloads, Homebrew or administrator installation. Explain the independent default-off CAD controls and the limits of changing type choices while a preview/thumbnail is already cached.

For a testable policy uncertainty, such as the deliberate extensionless-text declaration, provide the exact declaration, bounded behavior and reason in the review correspondence. A support answer or another app's approval is not preapproval of SpacePane. Keep the current app functional while seeking clarification.

## 10. Submit, diagnose and respond

### Submission sequence

1. Finish the version metadata, screenshots, privacy publication, compliance answers, pricing and availability.
2. Select the processed candidate in the macOS version's **Build** section and save. Resolve “Missing Compliance” before proceeding. [Apple: choose a build](https://developer.apple.com/help/app-store-connect/manage-builds/choose-a-build-to-submit)
3. Choose **manual release** for the first version unless a different launch plan is agreed.
4. Add complete App Review contact, notes and attachments; verify no placeholder remains.
5. Click **Add for Review**, inspect the resulting draft submission, then **Submit for Review**. The first button alone does not submit. [Apple: submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)
6. Record the submission/build and monitor App Review messages. Preserve the exact artifact; do not silently replace it while investigating a report.

Do not plan a fixed launch time on an assumed review turnaround. Leave room for a requested clarification, a rebuilt candidate and retesting.

### Diagnose the failing stage

| Symptom | First evidence to inspect | Appropriate response |
| --- | --- | --- |
| Archive fails locally | Build log, effective IDs, resources and native dependency output | Fix build inputs; this has not reached App Review. |
| Invalid signature/profile or ITMS-90287 | The named executable, its final signed entitlements and embedded profile | Correct the owning target's distribution setup, rebuild, inspect and validate again. |
| ITMS-90296 sandbox error | Nested executable named by Apple, not only the main app | Inspect both workers/service; maintain the correct independent vs inherited sandbox roles. |
| Quarantine attribute flagged | `xattr -r -l` on the staged candidate | Locate the copied input and correct the build/package process; do not strip attributes across user folders. |
| Build uploaded but unavailable | Processing status/email, version/build mapping, compliance state | Resolve the reported processing issue; upload success alone is insufficient. |
| Extension absent in Settings | Correct installed build, embedded bundle metadata, signing, stale development copies | Reproduce in a clean environment; correct packaging/registration causes. |
| Extension present but wrong preview | Enabled state, fixture's resolved UTType, actual provider | Distinguish disabled from not selected; inspect exact type mappings. |
| Extension starts then shows error | Scoped file availability, sandbox denial, budget/cancellation result | Repair the specific boundary; do not assume broader entitlements are the fix. |
| CAD works locally but not in beta | Delivered client signature and XPC requirement result | Investigate the authentication gate in section 5, then real host request behavior. |
| Reviewer cannot reproduce | Exact OS, build, activation route, fixture and expected result | Send concise steps and a harmless sample; fix a genuine defect before resubmitting. |
| App approved but not on sale | Release option, agreements, region availability and account compliance | Check distribution state separately from review approval. |

Quarantine is a documented native-Mac upload concern: Apple's requirement effective February 18, 2025 excludes `com.apple.quarantine` from files inside uploads for both TestFlight and the Mac App Store. The existing checker already checks it. [Apple: requirements](https://developer.apple.com/news/upcoming-requirements/)

### Rejections and clarification

Read the exact guideline and reproduce the reported steps with the submitted build. Separate metadata corrections from binary defects. Apple permits resubmitting a metadata-only rejection with the same build after correction. Reply in App Store Connect with facts and attachments; unresolved rejected items must be handled before a combined submission completes. [Apple: reply to review](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/reply-to-app-review-messages), [unresolved issues](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/manage-a-submission-with-unresolved-issues)

Suggested response:

> Regarding guideline [number], we reproduced [specific issue] on [OS/build]. The cause was [verified cause]. We changed [behavior or metadata] in [build/version]. To verify: [short numbered steps]. The attached [synthetic sample/recording] shows [expected result]. No separate installer or account is required [only if true].

If it is a policy disagreement and the app actually complies, use Apple's appeal route with the cited requirement and concise supporting evidence. Do not present a competitor's existence as proof that the app must be approved. [Apple: after submission and appeals](https://developer.apple.com/app-store/review/guidelines/#after-you-submit)

The [historical cases](../initial/08-app-store-publishing-research.md) include confirmed profile, signing, window-reopening and reviewer-instruction fixes. They also include unanswered Quick Look reports. Use the case's outcome label before treating it as a remedy.

## 11. Release and maintain the app

With manual release, approval leads to **Pending Developer Release**; use **Release This Version** when ready. Apple's publication can take up to 24 hours to appear. Confirm the product is actually available before announcing immediate availability. [Apple: release options](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option)

### Release-day verification

- Check the actual product page, supported devices, version, screenshots, links and intended storefront prices.
- Install the Store-delivered app in a normal environment and repeat first launch, shared settings, preview, thumbnail and app-quit smoke tests.
- Test the final CAD client signature and a synthetic model if CAD ships.
- Confirm support at info@spacepane.com is monitored and replies can be sent; keep the public policy available.
- Confirm recipients can obtain the dependency materials required by the approved license route.
- Preserve the release evidence and dSYMs; prepare a hotfix from a known source state.

Ask support reporters for macOS version, SpacePane version/build, chip, file suffix, affected surface, whether bytes are downloaded, and whether SpacePane's provider can be identified. Prefer a minimal synthetic reproducer. Do not ask for private documents or credentials as a routine diagnostic. A file shown by another provider may need a routing explanation, not a parser fix.

### Updates and recovery

Use the same app record and stable technical identifiers. Create the next version, increment the build, check inherited metadata and repeat the relevant release checks. Apple does not provide a simple rollback to a previous released version; a correction needs a new version submitted for review. [Apple: create a new version](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version)

For eligible macOS updates, phased automatic release runs over seven days and can be paused for up to 30 total days. Users can still download manually; pausing does not revoke installed copies. This is an update mechanism, not a phased first launch. [Apple: phased release](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases)

Prioritize regressions in source integrity, privacy, settings migration and helper authentication. Test updates with existing type overrides and themes; preserve default-off CAD. Reassess disclosure, licensing and provider claims whenever a dependency or new format changes them. Keep commerce, if later added, outside Quick Look rendering; do not introduce receipt checks or a license server merely because the app is paid upfront.

## 12. Final go or no-go checklist

These are proposed release gates. None is marked complete by this research.

### Identity and business

- [ ] Existing App ID and App Store Connect record match the final archive and nested targets.
- [ ] Signing profiles/certificates and App Group authorization are valid for the chosen distribution route.
- [ ] Agreements, tax/banking and applicable trader/account compliance are resolved.
- [ ] Existing regional price schedule and availability are verified without unintended changes.

### Product and artifact

- [ ] CAD licensing and corresponding-source/relinking route are approved before distributing the dependency.
- [ ] If CAD ships, accepted-client authentication passes on Apple-delivered code and rejects unauthorized clients.
- [ ] Final source checks/tests/compiler checks and archive checker pass, with recorded scope.
- [ ] Organizer validation, upload processing and final nested signature/entitlement inspection pass.
- [ ] The delivered candidate passes real Finder preview/thumbnail checks on macOS 15 and the current stable OS.
- [ ] Clean install, upgrade, close/reopen, companion-quit lifecycle, type policy and App Group settings are verified.
- [ ] Source/sidecar nonmutation, concealment and bounded cancellation remain validated.
- [ ] Shipping languages and accessibility claims have actual reviewed evidence.

### Store and review

- [ ] Description, screenshots and website match the validated release scope and architecture.
- [ ] Support and privacy pages show **info@spacepane.com**, and contact delivery is tested.
- [ ] Privacy answers are published; manifest applicability, age rating and export answers are recorded.
- [ ] Review notes are concise, current and free of placeholders; attachments are synthetic and tested.
- [ ] The selected build is the tested candidate; manual/automatic release choice is deliberate.
- [ ] Publishing authorization is obtained for the later submission/release action.

Stop if any critical gate lacks evidence. A deadline, successful upload, parser test count or approval of a similar app does not replace it. Track each unresolved item in PLAN or the release issue with its owner, required evidence and next action.

### Suggested evidence record

```text
Version / build:
Commit / clean working tree:
Archive location / checksum / dSYMs:
Xcode / SDK / OS / hardware:
Bundle IDs / group / profile verification:
Organizer and processing results:
TestFlight candidate and test matrix:
CAD license route and delivered-client test:
Approved format and language claims:
Privacy / age / export answers:
Price and availability verification date:
Review fixtures / notes / contact:
Reviewer correspondence and resolution:
Store release time and production smoke results:
```
