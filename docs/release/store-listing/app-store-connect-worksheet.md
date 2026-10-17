# SpacePane — App Store Connect worksheet for 1.0.0 (draft)

**Amended 2026-10-17:** the version in review is 1.1.0 (build 5), submitted 2026-10-17 at 11:08 and Waiting for Review; the 1.0.0 (3) and 1.1.0 (4) submissions were removed and no 1.0.0 submission remains ([version-1.1.0.md, status table](../version-1.1.0.md#submission-status)). The release option is Automatic in App Store Connect, against the Manual this worksheet and the readiness plan ask for. Section 3 below describes 1.0.0 and is superseded where the 1.1.0 record differs.

Status: draft answers, written 2026-10-10 from the repository and annotated on 2026-10-12 with what App Store Connect was observed to hold that day. Amended 2026-10-13: version 1.0 ships without STEP and IGES ([decision 028](../../decisions/028-no-cad-in-version-1.md)), so the submission build is build 3 without CAD, build 2 (which has CAD) is for internal TestFlight testing only, and the description and keywords stored in App Store Connect are out of date and are re-pasted from [../app-store-listing.md](../app-store-listing.md). Several answers are now entered there (marked "Entered" below); screenshots, the build selection, review notes and the attachment are not. [../app-store-listing.md](../app-store-listing.md#what-app-store-connect-holds) records the full list. App Store Connect's forms change; the owner confirms every answer against the live form on the day of entry. Where this worksheet and App Store Connect differ, App Store Connect is the record. The review notes, the archive and upload steps and the sample-file zip are in [../app-store-submission.md](../app-store-submission.md) and are not repeated here. Listing text is in [../app-store-listing.md](../app-store-listing.md) ([listing.en.md](listing.en.md) is a pointer to it); screenshots in [screenshots.md](screenshots.md).

"Basis" names the file that supports an answer, so the owner can recheck it.

## 1. App information

| Field | Answer | Basis / note |
|---|---|---|
| Name | `SpacePane for Quick Look` (24 characters; limit 2 to 30) | [../app-store-listing.md](../app-store-listing.md), owner decision 1 there; fallbacks are listed in that file. The installed app keeps the name `SpacePane` from `Configuration/Branding.xcconfig`. |
| Subtitle | `Preview JSON, SQLite, Markdown` (30; limit 30) | [../app-store-listing.md](../app-store-listing.md) |
| Bundle ID | `org.webmeister.spacepane` | Publication plan; set in the git-ignored `Configuration/Local.xcconfig`. Used by build 1.0.0 (1), uploaded 2026-10-10. |
| SKU | `org.webmeister.spacepane`, as found on the app record on 2026-10-10 | Never shown to customers. |
| Primary language | English (U.S.) unless the owner prefers another English variant | Development language is `en` (`tools/localization/languages.json`). |
| Primary category | Utilities. Entered (observed 2026-10-12). | `PREV_APP_CATEGORY = public.app-category.utilities`, `Configuration/Branding.xcconfig`. |
| Secondary category | Developer Tools. Entered (observed 2026-10-12). | Owner decision recorded in the publication plan. |
| Content rights | Entered (observed 2026-10-12): "does not contain third-party content". Reasoning: the app does not contain, show or access third-party content. The files it previews are the user's own. | Owner confirms. Bundled third-party material is software and data under licence, not content: five MIT-licensed colour palettes (`ThirdPartyNotices/ColorSchemes/NOTICE.md`) and, in builds that include the CAD helper (build 2; not the 1.0 submission build, decision 028), the pinned OCCT kernel (`ThirdPartyNotices/OCCT/`, `docs/dependencies/occt.md`). If the owner prefers to answer "Yes", the rights are documented in those notices. |
| Copyright | `2026 Can Burak Sofyalioglu`. Entered (observed 2026-10-12). | `PREV_COPYRIGHT` is "Copyright © 2026 Can Burak Sofyalioglu. All rights reserved." in `Configuration/Branding.xcconfig`; the App Store field takes the year and rights holder only. Owner confirms the rights holder is the seller named on the developer account (the bundle prefix `org.webmeister` suggests another organization may exist). |
| License agreement | Apple's standard end user licence agreement | Default; no custom EULA is drafted. |
| Tax category | App Store software. Entered (observed 2026-10-12). | Per the publication plan. Set under the app's pricing and availability. |

## 2. URLs

| Field | Value | Note |
|---|---|---|
| Marketing URL | `https://spacepane.com` | Optional field. Entered. |
| Support URL | `https://spacepane.com/support` | Required. Entered. The support, privacy and open-source pages are live (observed 2026-10-12); recheck on the day. |
| Privacy Policy URL | `https://spacepane.com/privacy` | Required. Entered. Same check. |
| Contact (public) | `info@spacepane.com` | Owner's active address; it is the contact address everywhere on the website (observed 2026-10-12). The domain has MX records (Hostinger), SPF and DMARC. Whether the mailbox answers is still unconfirmed. |

Open inconsistency, for the lead and the website stream, not changed here: `Configuration/Branding.xcconfig` (`PREV_SUPPORT_URL`, `PREV_PRIVACY_POLICY_URL`) and `../app-store-submission.md` still use the `.html` forms `https://spacepane.com/support.html` and `https://spacepane.com/privacy.html`, which belong to the old static `Website/` (now in the `spacepane-web` repository). The About links inside the app and the URLs entered in App Store Connect should resolve to the same live pages. Check both forms respond on the deployed site and pick one.

## 3. Version information (1.0.0; superseded by 1.1.0 build 5 on 2026-10-17)

| Field | Answer |
|---|---|
| Version | 1.1.0 since 2026-10-17 (`MARKETING_VERSION` in `Configuration/Base.xcconfig`; the record in [../version-1.1.0.md](../version-1.1.0.md)). History: the App Store Connect version record read 1.0.0 on 2026-10-12. |
| Build | 1.1.0 (5), uploaded 2026-10-17 10:39, submitted 11:08, Waiting for Review. History: build 1.0.0 (1) was uploaded on 2026-10-10 and never submitted; build 2 (2026-10-12, with CAD) was internal TestFlight only; the 1.0.0 (3) submission of 2026-10-13 and the 1.1.0 (4) submission of 2026-10-15 were removed. |
| Promotional text, description, keywords, What's New | [../app-store-listing.md](../app-store-listing.md) |
| Screenshots | The plan in [../app-store-listing.md](../app-store-listing.md); the per-shot checks in [screenshots.md](screenshots.md) |
| Sign-in required | No. There are no accounts. |
| Review contact first name | Entered in App Store Connect (observed 2026-10-12); not recorded in the repository |
| Review contact last name | Entered in App Store Connect (observed 2026-10-12); not recorded in the repository |
| Review contact phone | Entered in App Store Connect (observed 2026-10-12); not recorded in the repository |
| Review contact email | Entered in App Store Connect (observed 2026-10-12); not recorded in the repository |
| Review notes | In App Store Connect since 2026-10-17: the block of 2026-10-15 (names build 5 and the three 1.1.0 samples). The block in [../app-store-submission.md](../app-store-submission.md#notes-for-app-review) was corrected on 2026-10-17 (banner button, `31-model.3mf`, no thumbnail or macOS 15 claim) and is pasted again only when the version is out of review. Use the current block, not a copy made earlier. |
| Attachment | `SpacePane-Review-Samples.zip` is attached (observed 2026-10-17), built by `python3 script/build_review_samples.py` (no STEP or IGES file in it since 2026-10-13; 36 files since 2026-10-15). |
| Release option | **Manual release** (recommended; owner decision R-4 of the review readiness plan). App Store Connect reads "Automatically release this version" for 1.1.0 on 2026-10-17 (as it did on 2026-10-12), so it still has to be changed; the field is editable while the version is Waiting for Review. It lets the owner check the approved build and the website link before customers can download. Alternatives are release immediately after approval or on a set date; none is needed for 1.0.0. |

## 4. Age rating (2026 questionnaire)

Result: **4+**, entered in App Store Connect (observed 2026-10-12). The owner must read each question on the live form and confirm the answer; Apple changed this questionnaire in 2025 and the wording, grouping and options on the day control. The groups below follow the structure the task named; if the live form differs, answer the live form on the same principle.

Principle: answer for the content and features SpacePane itself provides, not for whatever a user might open with it. The app supplies no media, text or imagery of its own beyond synthetic sample files and interface text, and shows only files already on the user's Mac.

| Group | Answer | Reason |
|---|---|---|
| Content descriptors (violence, horror or fear, sexual content or nudity, mature or suggestive themes, profanity or crude humour, alcohol, tobacco or drug references, medical or health information, gambling and contests) | None for every item | The app has no such content. |
| In-app controls (parental controls, age assurance) | No | Not provided; not needed for a local viewer. |
| Capabilities | | |
| - Unrestricted web access | No | No web view and no network entitlement. Links in the About page and the website open in the user's browser. If the live form treats "links that open a browser" as web access, the owner decides; the app itself has no browsing surface. |
| - User-generated content | No | The app does not let users publish or share content. |
| - Messaging or chat | No | |
| - Advertising | No | No advertising. |
| Social media | No | No social features. |

Record the final rating Apple shows after submission. If it is not 4+, find which answer caused it before changing any.

## 5. App Privacy

**Answer: Data Not Collected.** Privacy policy URL as in section 2. No tracking. Entered in App Store Connect but **not yet published** (observed 2026-10-12).

Justification (one paragraph, grounded in the entitlements read on 2026-10-10 from `Configuration/*.entitlements`): the app, the preview extension, the thumbnail extension, the 3D import service and the 3D helper all run in the App Sandbox, and none of the five entitlement files contains `com.apple.security.network.client` or `.server`, so none of them can open a network connection. The app additionally holds only user-selected read/write file access (used for files the user explicitly exports, such as a theme) and the shared App Group; the two Quick Look extensions hold only the sandbox and the same App Group; the 3D service holds only the sandbox; the helper holds the sandbox and `com.apple.security.inherit`. There is no analytics, advertising, crash-reporting or other third-party SDK: `Package.swift` and the Xcode project declare no package dependencies, and a search of the Swift sources on 2026-10-10 found no `URLSession`, network framework or web-view use. Settings and profiles stay in the App Group container on the Mac. Nothing leaves the device, so nothing is "collected" in Apple's sense. The archive checker `script/check_release_archive.py` rejects `cs.*`, temporary-exception and network keys in the signed archive, and the app, both extensions and the 3D service each carry a privacy manifest (`PrivacyInfo.xcprivacy`).

Open checks: (a) read the entitlements of the signed archive, not only the source files (the checker does this on a real archive: record its output); (b) if any later change adds a network entitlement, an SDK or crash reporting, this answer and the privacy policy must be revisited before that build ships.

## 6. Export compliance

Info.plist: `ITSAppUsesNonExemptEncryption` is `false` in `Configuration/App-Info.plist` (the app target only; the extensions' plists do not set it). That answers "No" to Apple's encryption question without a per-build prompt.

**The open check the owner must close before relying on it:** that no reader in the product decrypts content or implements encryption of its own. What a search of the shipped sources (`Packages/`, `Apps/`, `Extensions/`, `Native/CADWorker/`) found on 2026-10-10 (the CAD helper's sources stay in the repository but are not in the 1.0 product, decision 028):

| Finding | Where | What it does |
|---|---|---|
| `import CryptoKit`, `Insecure.SHA1.hash`, `SHA256.hash` | `Packages/PreviewCore/Sources/PreviewFormats/Packages/TorrentAdapter.swift` | Computes the torrent info-hash (hashing, not encryption). |
| `import CryptoKit`, `SHA256.hash`, `Insecure.SHA1.hash` | `Packages/PreviewCore/Sources/PreviewFormats/Packages/CertificateAdapter.swift` | Shows certificate fingerprints (hashing). |
| `import CryptoKit`, `SHA256.hash` | `Packages/PreviewCore/Sources/PreviewFormats/Containers/CompressedStreamXZ.swift` line 118 | Verifies the XZ stream's SHA-256 integrity check (hashing). |
| `import Security`, `SecCertificateCreateWithData`, `SecCertificateCopyValues`, `SecCertificateCopyKey`, `SecKeyCopyAttributes` | `CertificateAdapter.swift`, `InstallerPackageAdapter.swift`, `ProvisioningProfileAdapter.swift` (same folder) | Reads certificate fields (inspection). No signature or chain is verified, no key is used. |
| `SecCode` information | `Packages/PreviewCore/Sources/PreviewFormats/Packages/CodeSigningSummary.swift` | Reads signer names from an application's code signature (inspection). |
| `CMSDecoder` (`CMSDecoderCreate`, `CMSDecoderUpdateMessage`, `CMSDecoderCopyContent`) | `ProvisioningProfileAdapter.swift`, enum `CMSContent`, around lines 96 to 117 | Extracts the content of a signed CMS message **without verifying it**. It calls `CMSDecoderIsContentEncrypted` and refuses (typed `encryptedContent` failure) if the content is encrypted. It does not decrypt. |
| Encrypted-entry detection only | `Containers/ZIPListingAdapter.swift`, `RAR4Listing.swift`, `RAR5Listing.swift`, `SevenZipStreamsInfo.swift` and `SevenZipListingAdapter.swift` (AES coder id recognised, not run), `Packages/DiskImageAdapter.swift` (`encrcdsa` and `cdsaencr` signatures), `Documents/EPUBAdapter.swift` and `EPUBPackage.swift` (DRM descriptors), `Documents/ComicBookAdapter.swift` | Entries and archives are flagged as encrypted and listed or refused. Nothing is decrypted. |

Not found: `CommonCrypto`, `CCCrypt`, any `AES`, `ChaChaPoly`, `SealedBox` or `SymmetricKey` use, `SecKeyCreateDecryptedData`, OpenSSL or other crypto libraries, or TLS code, in the Swift, C and C++ sources of the packages, app, extensions and the CAD helper. There are no remote Swift package dependencies. The pinned OCCT kernel in the CAD helper is a geometry library; its notices (`ThirdPartyNotices/OCCT/`) list no cryptographic component, and the helper has no network entitlement. (I searched the repository's own source and notice files. I did not scan the compiled OCCT static libraries for symbols; the owner may want that if certainty is needed.)

Reading of the findings, offered as information and not as legal advice: the only cryptographic API use is hashing and certificate-field parsing for display, and encrypted content is detected and refused, never decrypted. That supports the plist value `NO`. The owner makes the declaration and should read Apple's export-compliance questions on the live form. Standard-hash and certificate-parsing uses are the part an owner might want to read against Apple's wording about "encryption" before answering.

If App Store Connect shows the encryption question for the uploaded build anyway, the answer is consistent with the plist: the app does not use encryption beyond what Apple's operating system provides, and none is implemented by the app. Confirm the exact options on the day.

## 7. Pricing and availability

| Field | Answer |
|---|---|
| Price | Paid upfront, USD 9.99 (owner decision D-C, 2026-10-10). Entered (observed 2026-10-12). The repository records no price table; App Store Connect holds the effective prices. |
| Base storefront, manual overrides | Base storefront United States, USD 9.99 (observed 2026-10-12). Manual overrides are not recorded here. |
| Availability | 175 regions available (observed 2026-10-12). Whether that is every storefront is not recorded. Check regional compliance questions that appear. |
| Pre-order | No. |
| In-app purchases and subscriptions | None. State nothing about them in the listing. |
| Tax category | App Store software. Entered (observed 2026-10-12). |

## 8. Agreements and account checklist (owner actions)

The Account Holder must do these; none can be done from the repository. Order is not significant, but the Paid Apps Agreement and the trader declaration block a paid release.

- [x] Accept any pending agreements shown in App Store Connect (banner or Business section). Observed on the owner's screenshot of the Business page, 2026-10-12 evening: the Free Apps Agreement and the Paid Apps Agreement are both Active.
- [x] Sign the **Paid Apps Agreement**; add tax forms and banking details for the seller. Signed by the owner on 2026-10-12: the agreement is Active (2026-10-12 to 2027-10-04), one bank account is Active with USD as both bank and royalty currency, and the two U.S. tax forms (certificate of foreign status, W-8BEN) are Active.
- [ ] **Digital Services Act trader status.** Declared by the owner on 2026-10-12 as a trader; the Compliance row shows "In Review" for 27 countries or regions, so the box stays open until Apple finishes. Declare whether the seller is a trader. A trader's name, address, phone number and email are shown on the product page in the EU storefronts, so the owner needs contact details they accept being public. A non-trader declares that instead. If no declaration is made, the app is not offered in the EU. Trader status: still "Set Up" on 2026-10-12.
- [ ] Consider the **App Store Small Business Program** (enrol before the first sales if wanted). Not observed.
- [ ] Confirm the support mailbox `info@spacepane.com` exists and answers. Mail records exist (MX at Hostinger, SPF, DMARC); delivery is unconfirmed as of 2026-10-12.
- [x] Publish the CAD source repository named in `Native/CADWorker/SOURCE-OFFER.md` (`canburaks/spacepane-cad-source`). It is public with release 1.0.0 (observed 2026-10-12). Not needed for 1.0 since 2026-10-13: the repository stays as it is and nothing new is pushed to it ([decision 028](../../decisions/028-no-cad-in-version-1.md)).
- [ ] ~~Resolve the "pending legal review" wording in the offer, before release (publication plan, section "Owner decisions", D-D).~~ Not applicable for 1.0 (2026-10-13): 1.0 ships without STEP and IGES, so no release relies on the offer; see [decision 028](../../decisions/028-no-cad-in-version-1.md), which closes decision 027 D20 for 1.0. The question returns only if CAD does ("Bringing CAD back" in that record). No legal review took place and no licence was bought.
- [ ] Confirm the final bundle identifier, the team and the seller name agree with the copyright line above. The copyright is entered; the comparison with the seller name is not recorded.
- [ ] Recheck Apple's current requirements pages on the day of submission; this worksheet is dated 2026-10-10.

## 9. Store metadata locales for the 14 app languages

Decision taken 2026-10-12 (owner rule: only reviewed languages ship): the store page is English (U.S.) and English (U.K.) at launch, and version 1.0 ships English only. The table is the mapping for later; the other 13 translations stay in the repository as drafts.

Metadata locales are the languages the store page text can be provided in. They are independent of what the app ships, but the listing must not advertise a language the app does not ship (guideline 2.3). The publication plan (D-B) recommends shipping English plus only the languages that get a recorded review; no language has one today (`tools/localization/languages.json`: drafts, native-speaker review pending).

| App language | Code | App Store metadata locale | Note |
|---|---|---|---|
| English | `en` | English (U.S.), also U.K., Australia, Canada | Primary. Choose one primary variant; others optional. |
| Turkish | `tr` | Turkish | |
| German | `de` | German | |
| French | `fr` | French (France) or French (Canada) | Choose one or both. |
| Chinese, Simplified | `zh-Hans` | Chinese, Simplified | |
| Japanese | `ja` | Japanese | |
| Hindi | `hi` | Hindi | |
| Kurmanji (Kurdish, Latin script) | `ku-Latn` | **None** | No store locale. The store page cannot be offered in it. |
| Russian | `ru` | Russian | |
| Indonesian | `id` | Indonesian | |
| Bengali | `bn` | Bangla (Bengali) | The brief for this draft says a locale exists; confirm that Bangla appears in the live App Store Connect locale list before planning copy. |
| Hausa | `ha` | **None** | No store locale. |
| Portuguese | `pt` | Portuguese (Brazil) or Portuguese (Portugal) | **Regional choice needed**; the app's `pt` resources do not say which. Needs a decision, ideally the variant the reviewer reads. |
| Spanish | `es` | Spanish (Spain) or Spanish (Mexico) | **Regional choice needed**, same reason. |

So 12 of the 14 app languages have a store locale; Kurmanji and Hausa have none. A language that has a locale still gets copy only after its app translation has a recorded review.

## 10. Pre-entry verification list

Do these on the store build before entering the matching fields:

1. The extension names in the listing, `SpacePane Preview` and `SpacePane Thumbnails`, match what System Settings shows.
2. The "Open System Settings" button in the banner at the top of the General page opens the right pane on the macOS versions tested; record the pane path for each version.
3. Both URLs in section 2 load, the privacy page says "no network access" in line with section 5, and the support page shows the contact address.
4. The description's list of types still equals `FormatCatalog.json` (81 `id` entries since decision 030 on 2026-10-14, counted 2026-10-17; 74 for build 3, 26 + 26 + 16 + 1 + 5; 76 with 7 in the media group until `cad.iges` and `cad.step` left the catalog on 2026-10-13). The live description says 74 for build 5.
5. Every screenshot gate in [screenshots.md](screenshots.md) has its observation recorded in `docs/validation/host-matrix.json`.
6. The signed archive's entitlements contain no network key (output of `script/check_release_archive.py`).
