# App Store submission worksheet

Updated 2026-10-10 for SpacePane (first written 2026-10-04, revised 2026-10-07). Use the [detailed publishing guide](app-store-publishing-guide.md) for the full workflow and [historical research](../initial/08-app-store-publishing-research.md) for problems and documented outcomes. Release gates remain in [PLAN M6](../../PLAN.md#m6--prepare-for-the-app-store-later).

The owner has created the App ID, name and pricing plans, and reports (2026-10-10) that the App Store Connect app record and API key exist and that the price, roughly USD 9.99 with local pricing, is set in App Store Connect. Preserve that setup. Active contact and support email: **info@spacepane.com**. This worksheet is a preparation aid, not a claim of submission readiness or authorization to upload/release.

The product-page text itself (name, subtitle, keywords, promotional text, description, screenshot plan) is in [app-store-listing.md](app-store-listing.md). It was entered in App Store Connect as a draft for English (U.S.) and English (U.K.) on 2026-10-10, with the support, marketing and privacy URLs from the table below; that file records what the record holds and what is still empty.

## Before archiving

- Resolve the CAD license distribution gate and define the reviewed release scope. Default-off CAD still ships its library.
- Check the effective signing configuration against the existing app record. Production identities recorded in PLAN must replace the committed compile-only placeholders through the existing local configuration.
- Increment `CURRENT_PROJECT_VERSION` for each new/replacement upload; keep the app and embedded bundle versions consistent.
- Preserve prior candidate archives: the following command replaces `.build/archive/Release.xcarchive`.

```sh
./script/build_and_run.sh --archive
```

The script produces the signed arm64 Release archive for Apple silicon into `.build/archive/Release.xcarchive` and runs `script/check_release_archive.py`. The script checks:

- store keys and the compiled icon
- quarantine attributes and architectures
- nested signatures and the exact entitlement set of each role (app, the two extensions, the CAD service and both CADWorker copies), one App Group array across the app and the extensions, a hardened runtime everywhere, signing identifiers equal to bundle identifiers and one team identifier, no `cs.*`, temporary-exception or network keys
- nested Info.plists free of `$(` and prototype identities, versions equal to the app's, extension identifiers prefixed by the app's, unique Quick Look content types
- CAD helper identifiers and the peer requirement values: the service's allowed-client identifier and team equal the preview extension's, and the preview's service identifier equals the service's
- a privacy manifest (`PrivacyInfo.xcprivacy`) in the app, both extensions and the CAD service, with Apple's reason codes for the file-timestamp, system-uptime and user-defaults categories the code uses
- bundled notices and dSYMs

These checks do not establish Organizer validation, App Store processing, Apple-delivered CAD authentication or Finder behavior. The checker's own tests run on Linux as part of the static gate (`python3 script/test_check_release_archive.py`); the first run on a real archive may still find profile-injected entitlement keys or a manifest placement the synthetic trees did not model, so read its notes rather than only its exit code.

Corrected 2026-10-10: an earlier version of this section said the App Store form of the CAD peer requirement (the Mac App Store certificate-marker branch) would be proven by a TestFlight install. It will not. A TestFlight-delivered app is signed with the "TestFlight Beta Distribution" certificate, whose leaf carries OID `1.2.840.113635.100.6.1.25.1` and not the Mac App Store marker `1.2.840.113635.100.6.1.9`. Measured on 2026-10-10 on one Mac against another vendor's TestFlight app: a requirement of the shape the CAD service emits (the `6.1.9` marker or the team organizational unit) fails `codesign --verify -R`, and adding the `6.1.25.1` branch makes it pass. The TestFlight branch was added to `CADPeerRequirement` in source on 2026-10-10 and is unit-tested (no Xcode build with it has been made yet); it is unproven until a TestFlight install. The Mac App Store marker branch can only be proven on a store-delivered build. After the first TestFlight build, run `codesign -d -r- <installed PrevPreviewExtension.appex>`, note which marker its leaf certificate carries, and preview a STEP file (decision 027, D27).

Then either open the archive in Xcode Organizer, choose **Validate App**, and distribute to App Store
Connect, or run `./script/build_and_run.sh --export` (inspect) and `--upload` (TestFlight); the hosted
pipeline in [the TestFlight runbook](testflight.md) does the same with an App Store Connect API key.
Distribution re-signs the app. After export, confirm the helper identities survived the re-signing
(`--export` prints them), and inspect both workers and the service, not just the companion worker:

```sh
codesign -d --verbose=2 --entitlements - SpacePane.app/Contents/Helpers/CADWorker
```

See the guide for the separate TestFlight and store-delivered XPC client test.

## Review sample files

```sh
python3 script/generate_host_fixtures.py
```

Inspect the printed fresh directory. Select a small synthetic set, test it on the candidate in Finder and add a README naming the expected result for each file. Package it as `SpacePane-Review-Samples.zip` and attach through App Review Information. Do not assume this generator validates every catalog format or guarantees provider routing. Never include the supplied private CAD model.

## Notes for App Review

**Template: replace bracketed fields and remove any feature that is not in the validated shipping build. Confirm the Notes field byte limit before pasting.** The exact System Settings labels must be checked on the listed OS; this wording gives the macOS 15 route.

Before pasting, confirm that https://github.com/canburaks/spacepane-cad-source is public: the source offer in `Native/CADWorker/SOURCE-OFFER.md` takes effect when it is published, and it is still marked pending legal review. The notes below do not claim a legal review. Apple's limit for this field is 4,000 bytes; with its bracketed fields still in place the quoted text is under 3,000 bytes, so re-count it after filling them in.

> SpacePane [version/build] is a macOS 15+ Apple silicon utility containing Quick Look preview and thumbnail extensions. The companion provides setup, per-file-type controls, themes and built-in samples. Processing is local. No account, separate installer or in-app purchase is required. The app is Apple silicon only.
>
> Tested review environment: [macOS version and chip]. Attached: SpacePane-Review-Samples.zip and its README.
>
> 1. Launch SpacePane. On macOS 15, open System Settings > General > Login Items & Extensions > Quick Look and confirm SpacePane Preview and SpacePane Thumbnails are enabled. The General page also opens System Settings. [Add the verified route for the current OS if different.]
> 2. Unzip the attachment. In Finder select [exact tested sample filename] and press Space. Expected: [specific SpacePane mode, controls and safe content]. The attachment README lists other tested examples and thumbnail expectations.
> 3. The synthetic [filename] contains an intentionally fake secret. SpacePane conceals likely secrets in its text presentation; the file itself is unchanged.
> 4. In File Types, disable [tested type], then request a fresh preview. When macOS invokes SpacePane, it shows a disabled state. Re-enable the type afterwards. Existing previews and cached thumbnails may retain earlier results.
> 5. The Theme page previews built-in samples with the selected appearance. These samples demonstrate the companion, independently of Finder provider selection.
> 6. Optional diagnostic: General > Developer Mode reveals Try Preview and Open File. This uses the same pipeline, but does not demonstrate which provider Finder selected.
>
> STEP and IGES previews are optional and off by default; enable the two types in File Types, then preview the supplied synthetic model. They run in an embedded sandboxed helper built on Open CASCADE, which is under LGPL 2.1; its source is at https://github.com/canburaks/spacepane-cad-source. The helper downloads and installs nothing, and CAD thumbnails do not show the model geometry.
>
> macOS chooses the Quick Look provider and hosts the extensions on demand, including while the companion is closed. SpacePane cannot force provider priority. Type switches control SpacePane's handling of requests, not provider selection. The preview extension declares exactly public.data only to preview files that have no filename extension as bounded text, and never for thumbnails. The com.quicklookpro.file.* identifiers in QLSupportedContentTypes are referenced aliases only; the app neither imports nor exports them.
>
> Review contact: [name and international phone]. Email: info@spacepane.com. Support: https://spacepane.com/support. Privacy: https://spacepane.com/privacy.

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
| Description: open-source line | Last paragraph of every listing language that has a description: "3D previews use Open CASCADE Technology under the GNU LGPL 2.1 with the Open CASCADE exception. The helper's source and the written offer for the library source: https://github.com/canburaks/spacepane-cad-source" | The LGPL route needs the offer to be shown to users. Keep it only while STEP and IGES ship; translate it for localized listings. About > Acknowledgements and https://spacepane.com/open-source carry the same pointer. |
| Copyright | Approved value from Branding.xcconfig | Match legal rights holder. |
| Version/build | Actual uploaded values; 1.0.0 | Increment build for a replacement upload. Build 2 was used by the 2026-10-10 dry run, so use a higher number for the first upload. |
| Compatibility | macOS 15+, Apple silicon only (`ARCHS = arm64`) | Run the candidate on the advertised OS range; macOS 15 has never been run. |
| Pricing/availability | Set in App Store Connect (owner, 2026-10-10: roughly USD 9.99, local pricing adopted) | App Store Connect holds the effective prices; verify agreements, territories and compliance. |
| Review login | Not required if accountless design is unchanged | Do not invent a demo account. |
| Review contact | Reachable person, email and phone with +country code | Confirm monitored contact details separately from the public support URL. |
| Release option | Manual recommended for first release | Approval and release are separate actions. |

On October 7, the legacy `.html` support/privacy URLs redirected to the canonical pages and returned HTTP 200; both live English pages still showed `support@spacepane.com`. The owner's active address is `info@spacepane.com`; the website change is in progress and must be live before submission. Live page availability does not prove mailbox operation or every translated page.

## Submission reminder

Select the processed tested build, resolve compliance, save metadata, publish privacy answers, attach the reviewed packet, choose **Add for Review**, then **Submit for Review**. Keep each validation result with the exact version/build. Do not submit until the guide's release gates and the later publishing authorization are complete.
