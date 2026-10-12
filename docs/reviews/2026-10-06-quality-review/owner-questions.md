# Owner questions — 2026-10-06

The decisions that [decision 027](../../decisions/027-best-in-class-quality-program.md) leaves to the owner, written as questions with their options, the lead's recommendation and the work each answer unblocks. Answers were recorded on 2026-10-06 by the lead under the owner's delegation ("use your judgment to make reasonable decisions"); each answer names the option taken and can be revisited by editing its line. The lead amends the records each answer names as the work lands. Numbers match decision 027. Evidence pointers name the report and finding or recommendation identifiers under this directory.

## Group A — needed before Wave 0 ends

**D8. Plural forms.** Decision 026's chrome needs counted sentences in 14 languages ("1,204 lines", "3 likely secrets hidden", "{8 keys}"), and the localization tooling rejects plural variants by design.
- Options: (a) build `.stringsdict` generation and validation with CLDR categories per language and a counted string API; (b) keep label-colon notation ("Lines: 1,204") in all chrome.
- Recommendation: (a). The strips and the privacy row are the program's most visible change, and Russian, French, Spanish and Portuguese need plural categories to read correctly; (b) stays the fallback until the tooling lands.
- Blocks: every count sentence (Q-23, Q-50, Q-51, Q-52, Q-61). Evidence: chrome CH-9, accessibility AL2, structured views SV20.
- Answer (2026-10-06): (a). Build the `.stringsdict` tooling (backlog Q-23, in progress). Until it lands, counts use plural-free label-colon forms.

**D13. Concealment recall.** Broader secret recognition will hide more ordinary values (for example every `*_key` outside a public allowlist).
- Options: (a) accept more over-concealment with a false-positive ceiling the recall test enforces, for example at most 2 % of lines in an ordinary-text corpus; (b) keep today's narrow matching; (c) widen only the value patterns (Stripe, Slack, Google, GitLab, npm, PGP, base64 PEM) and not the key names. Separately: do URL credentials and the new formats get their own finding kinds, each needing wording in 14 languages, or count as the existing sensitive-field kind?
- Recommendation: (a) with the ceiling, and the existing kind for now; typed kinds can follow once the privacy row exists.
- Blocks: Q-01, Q-16. Evidence: security SP-01, SP-03, R1, R3.
- Answer (2026-10-06): (a), with a false-positive ceiling of 2 % of lines in the ordinary-text corpus and a recall target of at least 95 % on the positive corpus. URL credentials and the new token formats count as the existing sensitive-value finding kind for now; typed kinds can follow once the privacy row exists.

**D14. Thumbnail withholding.** May a content thumbnail be withheld when the concealed text or the file name merely looks credential-bearing (long mixed-case runs, `-----BEGIN`, names containing `secret`, `token`, `kubeconfig`, `id_rsa`)?
- Options: yes; no.
- Recommendation: yes. A false positive costs a generic glyph; a miss persists in Finder's durable cache.
- Blocks: Q-17. Evidence: security SP-04, R4.
- Answer (2026-10-06): Yes.

**D6. Thumbnail policy bundle.** Four related choices.
- D6a. Should CSV, TSV and SQLite thumbnails become shape-only (header band, column kinds, counts, no cell values), amending decision 022 which draws the first rows? Recommendation: yes; personal data in a customer export is not a credential, so concealment does not protect it.
- D6b. When SpacePane declines a thumbnail (switch off, type off, generic policy, a transient failure), should Finder get SpacePane's badged glyph or an error reply that leaves the system icon? Recommendation: an error for transient failures once the Wave 1 cache check shows how Quick Look treats errors; a badged glyph for policy decisions on secret-bearing text types.
- D6c. If iCloud generates and syncs these thumbnails (to be verified), should files in synced folders get text, a shape, or the glyph? Recommendation: defer until verified; if it syncs, the glyph.
- D6d. Keep content thumbnails on by default once tables are shapes? Recommendation: yes.
- Blocks: Q-10, Q-121, Q-124, Q-127, Q-131, Q-114. Evidence: thumbnails TH-05, TH-06, TH-09, questions 1–3 and 5.
- Answer (2026-10-06): D6a yes (decision 022 is amended when the shape-with-counts grid lands). D6b an error reply for transient failures once the Wave 1 cache check shows how Quick Look treats errors, a badged glyph for policy decisions. D6c deferred until iCloud behaviour is verified; if thumbnails sync, synced folders get the glyph. D6d yes.

**D16. Notebook figures.** Any notebook with a figure over about 24 KiB fails today because one base64 line exceeds the line limit. May Source show an inert placeholder instead of the exact base64 for image outputs, so that realistic notebooks preview at all?
- Options: yes; no (keep exact source and the failure).
- Recommendation: yes; the figures stay in Pages and the placeholder names them.
- Blocks: Q-15. Evidence: documents DM-13, R9; decision 020's "limitation to decide".
- Answer (2026-10-06): Yes.

**D17. Three mode questions.**
- D17a. `.ipa`, `.apk`, `.pkg` and torrents open on Files today; decision 017 says Summary. Keep 017 (fix the code) or amend 017 (keep Files)? Recommendation: keep 017.
- D17b. Is a SQLite data grid with a table picker, which decision 018 left out, in this program? Recommendation: yes, as a Wave 3 item after the contracts.
- D17c. May Invisibles leave the segmented control (opened from the privacy row instead), so no format exceeds five segments? Recommendation: yes.
- Blocks: Q-13, Q-60, Q-65. Evidence: structured views SV9, SV10, SV21.
- Answer (2026-10-06): D17a keep decision 017 and fix the code. D17b yes, as a Wave 3 item. D17c yes.

**D18. Citation terms.** The References mode builds APA, MLA, Chicago and IEEE citations with English terms ("et al.", "n.d.", "pp.", "(Ed.)") in every interface language.
- Options: (a) record the exception in decision 015 and say so in the References notice; (b) localize the terms.
- Recommendation: (a). The style guides define those terms in English; translating them would misrepresent the styles.
- Blocks: Q-08. Evidence: accessibility AL14, R7.
- Answer (2026-10-06): (a). The exception is recorded in decision 015 and stated in the References notice.

**D19. System names in setup copy.** macOS ships no Bengali, Kurmanji or Hausa interface, and the German, French, Spanish, Portuguese and Russian strings say "Quick Look" where Apple's own interfaces use their localized names.
- Options for bn, ku-Latn, ha: (a) English system names; (b) English with a translation in parentheses; (c) translated only. For de, fr, es, pt, ru: Apple's names from the localization glossaries, or keep "Quick Look".
- Recommendation: (b) for the three, and Apple's names for the five, with one separator everywhere; record the policy in decision 008.
- Blocks: Q-112, the setup trail (Q-93). Evidence: accessibility AL8, R8.
- Answer (2026-10-06): (b) for Bengali, Kurmanji and Hausa. Apple's own names for German, French, Spanish, Portuguese and Russian once a Mac session confirms them in System Settings; one separator everywhere; the policy is then recorded in decision 008.

**D15. Copying invisible payloads.** Decision 012 copies Source byte for byte. May Copy, Copy All and Copy Concealed Text remove Unicode Tag characters outside valid flag sequences when the Safety Lens found a tag payload, with the Copied chip saying so?
- Options: yes; no.
- Recommendation: yes; a hidden instruction payload otherwise survives every copy, and Invisibles mode still shows the markers.
- Blocks: Q-155. Evidence: security SP-09, R12.
- Answer (2026-10-06): Yes.

**D25. Verification infrastructure.** Four choices.
- D25a. Add a GitHub Actions workflow on hosted macOS runners (runner minutes; repository visibility) and make it a required check? Recommendation: yes; it is the compiler for every cloud session.
- D25b. Allow a development-only Python dependency (`tree-sitter`, `tree-sitter-swift`) for the Swift syntax gate? It never ships. Recommendation: yes.
- D25c. Finish the `NativePreviewView` decomposition, compiled and merged, before any decision 026 workstream branches? It costs about a week up front and removes most integration conflicts. Recommendation: yes.
- D25d. `script/generate_project.py` no longer reproduces the checked-in Xcode project. Retire it, or repair it and check it? Recommendation: retire it and make the checked-in project the source of truth, unless someone maintains the generator.
- Blocks: Q-19, Q-21, Q-31, Q-173. Evidence: architecture AR-01, AR-03, AR-09, R2–R4.
- Answer (2026-10-06): D25a yes, with the macOS job on manual dispatch (the repository is private, so macOS minutes are billed at ten times the rate) and the Linux static job on every push. D25b yes. D25c yes. D25d retire the generator once a Mac session confirms nothing depends on it; until then it is documented as not reproducing the project.

**D5 (reframed). The website's STEP claim.** The site makes no STEP exclusivity sentence; the issue is that STEP, which is off by default, leads the hero and the tour, and that routing sentences read as promises.
- Options for the hero: (a) keep the STEP tile and label it opt-in; (b) lead with a default-on format and keep STEP in the tour with an "off by default" note. For routing sentences: accept "when macOS uses SpacePane for the type" on each, or leave them.
- Recommendation: (b), and accept the hedge.
- Blocks: Q-09. Evidence: platform PI-19, PI-20.
- Answer (2026-10-06): (b): the hero leads with a default-on format and STEP stays in the tour marked off by default; the hedge is accepted on every routing sentence.

## Group B — needed before Wave 2

**D1. Which structured formats open in a structured view first?** The code opens Source for JSON, YAML, TOML, XML and property lists; the original design and the data references lead with a tree. The evidence and three options are in the structured-views report; the Finder matrix's YAML row is re-run in Wave 1 first.
- Options: (a) Outline first for JSON and property lists (whose Source is generated JSON anyway), Source first for YAML, TOML and XML until their outline subsets are fixed; (b) Outline first wherever the outline could be built, Source otherwise (the opening view then depends on size); (c) Source first everywhere, with default-first ordering making Outline the second segment. Also: JSON Lines opening in Records and `package.json` in Summary, as the original design put them?
- Recommendation: (a), with (b)'s fallback for JSON files the outline cannot hold, plus Records and Summary for the two named formats. The outline is already built eagerly for every JSON display, so Outline-first probably closes most of the 434 ms warm gap; Wave 1 measures it.
- Blocks: Q-60, Q-101, Q-32's `primaryView` field. Evidence: structured views "Evidence for the owner decision", performance PF-02.
- Answer (2026-10-06): (a) with (b)'s fallback for JSON: Outline first for JSON and property lists when the outline can be built, otherwise Source; Source first for YAML, TOML and XML until their outline subsets are fixed (the YAML defect SV4 is fixed in Round 1, so YAML is re-evaluated after the Wave 1 re-run); Records first for JSON Lines; Summary first for package.json. Implemented through `PreviewModePolicy` after the Wave 1 measurement.

**D2. A prose face for Markdown, notebooks and ebooks.**
- Options: (a) a fixed system text face with no setting (no schema change; the chosen code family then applies to code only in Rendered); (b) a selectable family as a schema 7 field with the migration the documents report lists.
- Recommendation: (a) now; revisit (b) after the program, so the preferences schema stays out of the critical path.
- Blocks: Q-71. Evidence: documents DM-02, R6.
- Answer (2026-10-06): (a): the system text face at the configured size, no setting; schema 7 is revisited after the program.

**D9. Principle 2 (keys the host owns).** Contents, Pages, 3D and diagrams bind Space and the arrow keys when focused, and tests pin it.
- Options: (a) never Space; arrows only inside a focused table, outline, page column, canvas or viewport, listed in the shortcut sheet; (b) remove Space and the arrows everywhere; (c) keep today's bindings.
- Recommendation: (a), subject to the Wave 1 observation that Space, Escape and the arrows still reach Quick Look when nothing of ours has focus.
- Blocks: Q-75, amendment 10. Evidence: documents DM-07, accessibility AL15.
- Answer (2026-10-06): (a), subject to the Wave 1 observation.

**D10. Overlays.** Contract 1 forbids overlays that cover content, and the same decision asks for a floating 3D control group and code-block copy buttons; it also plans both a dimensions chip and dimensions in the facts strip.
- Options: accept the 3D control group and margin copy buttons as the only exceptions; dimensions in the facts strip, not a chip.
- Recommendation: yes to both.
- Blocks: Q-81, Q-73. Evidence: documents DM-14.
- Answer (2026-10-06): Yes to both.

**D11. The muted tier in Solarized Light, Solarized Dark and One Dark.** Those schemes' published foregrounds leave too little headroom for a 4.5:1 muted tier to look lighter than body text.
- Options: (a) accept muted equal to the foreground with hierarchy by size and the hairline, as a recorded exception; (b) darken those schemes' published foregrounds.
- Recommendation: (a); the schemes' identity is their published colours.
- Blocks: Q-34, gate 4 (amendment 7). Evidence: chrome CH-7, accessibility AL7.
- Answer (2026-10-06): (a).

**D12. When the extension answers Quick Look.** Today the completion handler is called after the whole pipeline and display, so Finder shows its own spinner and SpacePane's loading state is never seen. The Wave 1 experiment observes both orders.
- Options after the experiment: (a) keep Quick Look's spinner (handler when content is ready); (b) call the handler early and show SpacePane's state view; (c) a grace period of about 150 ms, then the state view.
- Recommendation: decide from the observation; the lead's prior is (c).
- Blocks: Q-41, Q-35's Finder behaviour, gate 2. Evidence: chrome CH-11, performance PF-05, platform PI-04.
- Answer (2026-10-06): Decided after the Wave 1 experiment; the prior is (c), a grace period of about 150 ms.

**D3. A bundled sample reveal.** May setup step 3 copy a synthetic sample file to a user-writable location and reveal it in Finder, on request only?
- Options: yes; no (step 3 points at the Theme sample).
- Recommendation: no for now; revisit after the setup trail ships.
- Blocks: Q-93 step 3. Evidence: self-audit C3, companion recommendation 4.
- Answer (2026-10-06): No for now.

**D7. Thumbnails for content-free system types.** After the Wave 1 table shows what the system draws when SpacePane does not register, may folders, apps, disk images, installers, archives, torrents and MIDI leave the system icon in place (`thumbnail: none`)? This narrows decisions 017 and 022.
- Options: yes where the system draws its own icon; no.
- Recommendation: yes; the glyph protects nothing there and removes recognisability.
- Blocks: Q-122. Evidence: platform PI-05, thumbnails TH-02.
- Answer (2026-10-06): Yes wherever the Wave 1 table shows the system draws its own icon.

**D4. Content-true 3D thumbnails for STEP and IGES, and the 3MF package picture.** Evidence: a CAD import costs about 0.5–1.1 s against a 1 s hard limit; geometry has no text to conceal; the thumbnail extension would need its own XPC service; a render of a proprietary part persists in the durable cache.
- Options: yes, opt-in per CAD type; no for 1.0; 3MF picture only.
- Recommendation: no for 1.0; STL, OBJ and PLY keep Apple's renders either way.
- Blocks: nothing in the program. Evidence: thumbnails question 4.
- Answer (2026-10-06): No for 1.0.

**D23. Four companion questions.**
- D23a. Command-comma: keep the standard "Settings…" title and select General, keep File Types as decision 010 says, or label the item by its destination as decision 026 says? Recommendation: the standard title, selecting General (an amendment to 010).
- D23b. Sidebar on macOS 26: classic sidebar vibrancy behind the existing list, or the system split-view sidebar for the glass look at the cost of suppressing its collapse behaviour (amending 010's mechanism)? Recommendation: vibrancy on 15 now; observe 26 before adopting the split view.
- D23c. Conflict scan: strictly on demand (decision 023), or run once when General first appears so step 2 and the File Types markers fill in? It reads other apps' bundles. Recommendation: on demand, with the button beside step 2.
- D23d. Should a metadata-only "Check this file" exist outside Developer Mode, given that "why is another app's preview shown" is the most common support question? Recommendation: keep it with Try Preview for now; revisit after the setup trail ships.
- Blocks: Q-98, Q-105, Q-99, Q-97. Evidence: companion questions 1–4.
- Answer (2026-10-06): D23a the standard "Settings…" title selecting General (amends decision 010). D23b vibrancy now; the split view only after observing macOS 26. D23c on demand, with the button beside step 2. D23d keep it with Try Preview.

**D24. CAD in the companion.** The companion's CAD worker inherits the companion sandbox (App Group, user-selected read-write). Should Try Preview and the Theme samples import CAD through an app-embedded, isolated XPC service, or should CAD previews be Finder-only?
- Recommendation: the embedded service, as a low-priority item; dropping CAD from the companion would also drop the STEP and IGES Theme samples.
- Blocks: Q-156. Evidence: security SP-14, R15.
- Answer (2026-10-06): The embedded service, at low priority.

**D26. Language of Finder previews.** Should Finder previews follow the companion's per-app language (a snapshot field, so a schema change), or is "each host follows its own language setting" acceptable and documented?
- Recommendation: document it; no schema change.
- Blocks: Q-162. Evidence: accessibility AL16, R14.
- Answer (2026-10-06): Document it; no schema change.

**D-chrome. Three chrome questions.**
- May provenance notes (signatures not verified, certificate trust not checked, CAD metadata omitted, Markdown offline, approximated formulas) move into the info panel, leaving the limits strip one line? Recommendation: yes.
- In compact width, may the gutter hide even when the user turned line numbers on, with the facts strip stating the line count? Recommendation: yes.
- Should the outline and table filter bars open on demand (gate 1), or stay visible as the analysis's "visible when idle" asks? Recommendation: on demand, with a visible search affordance in the header.
- Blocks: Q-51, Q-53, Q-55, Q-62. Evidence: chrome questions 1, 3 and 4.
- Answer (2026-10-06): Yes to all three; the filter bars open on demand behind a visible search affordance in the header.

**D-3D. Up axis.** STL and 3MF are Z-up by printing convention; CAD exchange files have no convention.
- Options: Z-up for STL and 3MF, Y-up for OBJ, and for STEP, IGES and PLY either Y-up until real files are observed or Z-up; with or without a per-view, never persisted "Up axis" toggle.
- Recommendation: Z-up for STL and 3MF, Y-up for the rest until observed, with the toggle.
- Blocks: Q-80. Evidence: documents DM-10, question 4.
- Answer (2026-10-06): Z-up for STL and 3MF; Y-up for OBJ, STEP, IGES and PLY until real files are observed; with the unpersisted toggle.

## Group C — needed before Wave 4

**D20. CAD in 1.0 and the OCCT obligation.** Static OCCT linking leaves a library-source and relinking obligation that is unmet.
- Options: (a) meet it by publishing the CAD worker's sources, the pinned OCCT archive, the manifest edits and the build script with a written offer (the worker is a separate five-file executable, so the Swift app is untouched); (b) ship 1.0 without STEP and IGES by build configuration.
- Recommendation: (a) with a legal review; (b) if the review cannot complete in time.
- Blocks: Q-171, store copy and About text. Evidence: platform PI-09, `docs/dependencies/occt.md`.
- Answer (2026-10-06): (a) with a legal review; (b) if the review cannot complete before submission.

**D21. If macOS 15.0–15.3 cannot load the build.** `isolated deinit` appears in nine production files and may need the Swift 6.1 runtime that shipped with macOS 15.4; the Wave 1 symbol check and a launch on 15.0–15.3 decide.
- Options: (a) raise the minimum to the first 15.x that works; (b) replace `isolated deinit`.
- Recommendation: (a); the website and store text then say that version.
- Blocks: the release copy, gate 18. Evidence: platform PI-03.
- Answer (2026-10-06): (a); the website and store text then name that version.

**D22. Languages in 1.0.** Thirteen translations are drafts; the store lists the bundle's languages.
- Options: (a) ship only reviewed languages; (b) ship all 14 and record the draft status.
- Recommendation: (a), since AGENTS says an advertised language needs reviewed translations; review the chrome, setup, state and failure strings first so more languages qualify.
- Blocks: Q-172, Q-113. Evidence: platform PI-11, accessibility AL13.
- Answer (2026-10-06): (a): reviewed languages only, with the chrome and setup strings reviewed first.

**D27. A TestFlight round before submission.** It is the only way to test the store-signed CAD peer requirement and the cleanest way to reach macOS 15.
- Recommendation: yes.
- Blocks: Q-44's proof, gate 18. Evidence: platform PI-02, question 6.
- Answer (2026-10-06): Yes.
