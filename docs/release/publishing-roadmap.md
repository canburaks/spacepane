# SpacePane 1.0 publishing roadmap

> **Snapshot, not current guidance.** This is the 2026-10-06 roadmap, recovered on 2026-10-10 from a stash in the former `prev` repository (it was never committed there) and filed here as history. Where it conflicts with the [TestFlight runbook](testflight.md) or the [publication plan](../plans/2026-10-10-app-store-publication-plan.md), those documents win. The text below the rule is unchanged except for this header.
>
> Points that are superseded:
>
> - **Support address.** The roadmap makes `support@spacepane.com` deliverable (decision 0.5). The owner's active address is `info@spacepane.com` (2026-10-10); the website and listing move to it.
> - **Account steps.** The owner reports that the App Store Connect app record and an API key now exist (phase 1, steps 3 and 4). Agreements, tax, banking and trader status are not confirmed.
> - **Price.** Decision 0.2 proposes a base price. The owner has set roughly USD 9.99 in App Store Connect with local pricing adopted (2026-10-10); App Store Connect holds the effective prices.
> - **Languages.** Decision 0.3 assumes the owner can review Turkish. The publication plan records that no language has a review record yet and that only reviewed languages ship (D-B).
> - **Minimum macOS.** Decision 0.4 suggests a macOS 15 virtual machine. The owner reports that no macOS 15 machine or virtual machine is available, so the question is open (D-I).
> - **Upload route.** Phase 2.9 and phase 4 upload from Organizer. The runbook uses `./script/build_and_run.sh --archive`, `--export` and `--upload` with an App Store Connect API key, which worked as far as export on 2026-10-10 (see the [dry-run record](../validation/2026-10-10-testflight-dry-run.md)).
> - **Age rating.** Phase 1, step 6 says to answer "None" everywhere. Apple replaced the questionnaire in 2026; see the [publishing guide](app-store-publishing-guide.md#age-rating).
> - **OCCT route.** Step 2.1 leaves the publication place open. The route now recorded is the public repository `canburaks/spacepane-cad-source`, still pending legal review (`Native/CADWorker/SOURCE-OFFER.md`).
> - **Store-signed CAD client.** The roadmap does not mention it. A TestFlight-delivered app carries the TestFlight certificate marker, not the Mac App Store marker, so the CAD peer requirement needs a third branch before TestFlight can work (fixed in source 2026-10-10; unproven until a TestFlight install; see the runbook).
> - **Schedule.** The "3 to 5 weeks" estimate dates from 2026-10-06 and has not been re-estimated.

---

Written 2026-10-06 from the changelog, [PLAN M6](../../PLAN.md#m6--prepare-for-the-app-store-later)
and a check of the repository and the live site. PLAN stays the source of truth for gates.
Tick items there, not here. Paste-ready review notes and App Store Connect answers are in
[app-store-submission.md](app-store-submission.md); some of them need refreshing (step 2.6).

Owner: **You** means only you can do it (account, legal, money or taste). **Claude** means the work
can be done in the repository.

## Where 1.0 stands

| Area | State |
| --- | --- |
| Build | Ready: signed Release archive passes `check_release_archive.py`; identity `org.webmeister.spacepane`, arm64, version 1.0.0 |
| Features | 76 formats, Safety Lens, content thumbnails, 11 color schemes, live reload, conflicts scan |
| Package tests | 2,452 Swift tests, integration checks and 648 adversarial cases pass |
| Website | Live at spacepane.com; `/privacy` and `/support` resolve, and the old `.html` links redirect |
| Support email | **Broken:** `support@spacepane.com` is published, but spacepane.com has no MX record, so mail bounces |
| OCCT licence (STEP/IGES) | **Open** release gate |
| Finder evidence | Only the early formats were seen in Finder; no new format, mode or thumbnail has been |
| Signed-host checks | **Not run** for live reload, sandboxed certificate/profile inspection, the conflicts scan and CAD on the new identity |
| Translations | 14 languages, all drafts without native review |
| Other platforms | macOS 15 and Intel never run; VoiceOver not checked |
| Store account | Pricing, agreements, trader status and store listing not started |

Realistic time to submission is **3–5 weeks**. Most of it is verification and waiting on Apple's
account checks, not code.

## Phase 0: Decisions (this week)

These unblock everything else. Each has a recommendation.

| # | Decision | Recommendation | Owner |
| --- | --- | --- | --- |
| 0.1 | **STEP/IGES in 1.0?** The CAD worker statically links OCCT (LGPL 2.1). | **Keep CAD and publish a corresponding-source package** (step 2.1). It is your clearest differentiator. LGPL **2.1** has no "installation information" clause, so the signed App Store bundle doesn't block compliance. Users only need the source and materials to relink the worker. Get a short legal confirmation. **Fallback:** remove STEP/IGES from the 1.0 build and add them in 1.1. | You |
| 0.2 | **Business model and price** | **Paid upfront**: no StoreKit code and no in-app purchase review. Comparable all-in-ones sell for $3.99–$9.99 one-time and nobody uses subscriptions. Set a base price with Apple's automatic regional prices, then adjust the storefronts you care about (country-specific prices are a requirement). | You |
| 0.3 | **Languages in 1.0.** The App Store lists every language in the bundle. | Ship English plus the languages a native speaker has reviewed. You can review Turkish yourself, so at least English and Turkish. Add the others in updates as reviews arrive. Shipping all 14 as drafts risks visibly poor wording in reviews and screenshots. | You decide; Claude builds the language filter |
| 0.4 | **Minimum macOS** | Keep **macOS 15**, but run it once in a macOS 15 VM (Phase 2). If something breaks and can't be fixed quickly, raise the minimum to 26 instead. | You |
| 0.5 | **Support address** | Make `support@spacepane.com` deliverable through your registrar's mail forwarding, Cloudflare Email Routing or ImprovMX, forwarding to your inbox. Or publish an address you already receive. | You |

## Phase 1: Account and store setup (start now; runs in parallel)

Some of these take days to verify, so start them before the engineering.

1. **Agreements, tax and banking.** In App Store Connect → Business, accept the Paid Apps agreement and add bank and tax details. You can't set a price until this is active.
2. **EU trader status (DSA).** As an individual trader, your name, address, phone and email are shown on the EU storefronts. Without it, the app is unavailable in the EU.
3. **App ID.** Register `org.webmeister.spacepane` (Explicit, no capabilities). Xcode registers the extension and XPC-service IDs when you validate.
4. **App record.** Apps → + → New macOS App: name "SpacePane", bundle ID `org.webmeister.spacepane`, SKU `spacepane-mac`. This reserves the name. Apple can release it if no build is uploaded within about 180 days.
5. **Support email** (decision 0.5). Send a test message from an outside address and confirm it arrives.
6. **Age rating.** Answer the questionnaire. SpacePane shows only the user's own files, so every content answer is "None".
7. **App Privacy.** Choose **Data Not Collected**. The app has no network entitlement, analytics or SDKs, and settings stay on the Mac.

**Exit:** agreements active, trader status verified, app record exists, support email delivers.

## Phase 2: Release-blocking engineering and verification (1–2 weeks)

| # | Task | Why it blocks | Owner |
| --- | --- | --- | --- |
| 2.1 | **OCCT compliance package** (if 0.1 = keep CAD): publish the pinned OCCT source archive, the build-manifest changes, `build_cad_worker.py`, and the CADWorker source or object files with relinking instructions, at a stable URL (a GitHub repo or spacepane.com/source). Then link it from the About acknowledgements and the notices. | Legal obligation for distributing the statically linked helper | Claude prepares; you publish and confirm |
| 2.2 | **Signed-host smoke test of features that have never run signed**: live reload, certificate/profile/package inspection (Security CMS under the sandbox), the Quick Look conflicts scan, and STEP/IGES through the XPC service on the new identity. | Code that has never run in a sandbox is the most likely crash or rejection under guideline 2.1 | Claude scripts it; you watch the Finder results |
| 2.3 | **Finder evidence for the launch claims.** Pick the 15–20 formats you'll advertise and run each in Finder (Space bar and thumbnail) on the signed build, using `generate_host_fixtures.py`. Record the results in a new Finder matrix. | Guideline 2.3: the listing must match what Finder actually does. Advertise only what you observed. | Claude prepares; you confirm in Finder |
| 2.4 | **macOS 15 run** in a VM (UTM or Virtualization.framework on Apple silicon): install, enable the extensions, preview 10 formats, open every companion page. | The deployment target is macOS 15 but nothing has run below 27.2 | You run it; Claude fixes what breaks |
| 2.5 | **Accessibility basics**: a VoiceOver pass over the four companion pages and one preview, plus keyboard-only navigation. | App Review checks UI quality; Accessibility Nutrition Labels may only claim what you verified | You, with Claude fixing |
| 2.6 | **Refresh the review notes** for the new features: Safety Lens, content thumbnails (on by default), live reload, the conflicts scan (reads other apps' Info.plists in `/Applications` only after the user clicks Scan, and sends nothing), and the provider badge. | Reviewers reject what they can't understand or find (guideline 2.1) | Claude |
| 2.7 | **Apply the language decision** (0.3): drop unreviewed `.lproj` folders from the release bundle with a build-time filter, so draft languages stay in the repo. | The store listing shows every bundled language | Claude |
| 2.8 | **Raise the build number** for every upload; keep 1.0.0 as the marketing version. | App Store Connect rejects repeated build numbers | Claude |
| 2.9 | **Archive → Organizer Validate App → export**, then confirm the re-signed CADWorker identifiers in the exported app. | Last local proof before upload | You (Organizer); Claude runs the checks |

**Exit:** `--archive` passes, Organizer validation passes, a Finder matrix exists for every advertised
format, and macOS 15 and signed smoke tests are recorded in `docs/validation/`.

## Phase 3: Store listing (2–3 days, alongside Phase 2)

- **Name** "SpacePane" (30-character limit). **Subtitle** describes the job, e.g. "Quick Look for code and data". Don't put "Mac", "Finder" or another app's name in the name.
- **Description:** what it does and which extensions it adds (guideline 4.4 requires naming them). List formats only from step 2.3. State limits honestly: macOS chooses the provider, files are read-only, and there is no network access. No "only", "best" or comparisons.
- **Keywords** (100 characters): format names and tasks. No competitor or Apple trademarks.
- **Screenshots:** 3–6 real captures at 2880×1800 (16:10):
  - Finder Space-bar previews: rendered Markdown, CSV Profile, the archive risk report, a Safety Lens finding, a STEP model
  - the Theme page
  - the File Types page

  Use synthetic files only, never real secrets or personal paths.
- **URLs:**
  - Support: https://spacepane.com/support
  - Privacy: https://spacepane.com/privacy
  - Marketing: https://spacepane.com
- **Category:** Utilities, with Developer Tools as the secondary category.
- **Pricing and availability:** from decision 0.2, per storefront.
- **Localized listings:** only for the languages shipped in 0.3.

## Phase 4: TestFlight beta (1–2 weeks)

1. Upload the build from Organizer. The first upload also checks signing and provisioning server-side.
2. **Internal testing:** you and other App Store Connect users, available within minutes, no review. Try:
   - a clean user account
   - macOS 15 (VM), 26 and 27
   - with QuickLookPro or Peek installed and without
   - first-run enabling of the extensions
3. **External testing** (optional; a public link for 10–20 friendly users) needs a short beta review. That review is a useful rehearsal for App Review.
4. Read the crash reports in Xcode Organizer → Crashes and fix them before submitting.

**Exit:** no crashes in a week of use, and enabling the extensions works on a clean account.

## Phase 5: Submit and review

- Choose **Manually release this version**, so approval doesn't publish before the website is ready.
- Paste the refreshed review notes, attach `SpacePane-Review-Samples.zip`, and add a 60-second screen recording: enable the extensions, then press Space on four files.
- Most reviews finish within 24–48 hours. If rejected, reply in App Store Connect with specifics before resubmitting; each rejection allows one appeal.
- Rejections most likely for this app, already addressed in the plan:

| Guideline | Risk | Mitigation |
| --- | --- | --- |
| 2.1 completeness | Reviewer can't find the extensions or hits a broken link | Review notes, samples, recording; working support email |
| 4.2 minimum functionality | App window seen as "just settings" | Theme live preview and the conflicts scan show the app's value; explained in notes |
| 2.4.5(iii) | "Processes keep running after quit" for the extensions | Notes say macOS owns the extension lifecycle (a known false positive Apple support has confirmed) |
| 2.3 accurate metadata | Advertised formats that Finder doesn't route | Advertise only formats from step 2.3 |
| 5.2.5 / 4.1 | Apple or competitor names in the name or screenshots | Name rules above; screenshots show only SpacePane UI |

## Phase 6: Launch and after

1. Release the approved build. On the website, replace "Coming soon" with Apple's official **Download on the Mac App Store** badge and link.
2. Watch Organizer crashes, App Store reviews and the support inbox daily for the first two weeks. Answer reviews politely.
3. **1.0.1** for crash fixes; Apple usually reviews bug-fix updates quickly.
4. **1.1 candidates:**
   - more reviewed languages
   - STEP/IGES, if deferred
   - the `proxy.ts` middleware once Netlify's plugin is fixed (in the `spacepane-web` repository)
   - retiring `Website/` (in the `spacepane-web` repository)
   - an Intel build, if customers ask (adding Intel later is allowed; removing it is restricted)

## What Claude can start now

1. Refresh `app-store-submission.md` with the new features and the conflicts-scan explanation (2.6).
2. Prepare the OCCT corresponding-source package and relinking instructions (2.1).
3. Add a release-only language filter, ready for decision 0.3 (2.7).
4. Write a signed-host smoke-test script and a Finder-matrix template for the advertised formats (2.2, 2.3).
5. Make the build number an explicit release step in `--archive` (2.8).
