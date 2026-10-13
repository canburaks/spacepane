# Store listing files

Updated 2026-10-13. The listing text is in one file: [../app-store-listing.md](../app-store-listing.md) (name, subtitle, keywords, promotional text, English U.S. and U.K. descriptions, claim check, screenshot plan, and what App Store Connect holds). It rests on [the listing research](../../market/2026-10-10-app-store-listing-research.md). The text from that file was entered in App Store Connect on 2026-10-10; the description and keywords stored there are out of date (they say "11 color schemes" and "76 file types" and carry the STEP and IGES wording) and are re-pasted from the listing file before submission. On 2026-10-13 version 1.0 was cut back to ship without STEP and IGES ([decision 028](../../decisions/028-no-cad-in-version-1.md)); the listing file is the copy for build 3, which has no CAD.

Files in this folder:

- [listing.en.md](listing.en.md): a pointer to the file above. The earlier draft was superseded on 2026-10-10 and removed on 2026-10-12; the file stays so links do not break.
- [screenshots.md](screenshots.md): the nine screenshots chosen on 2026-10-12 (the models scene is to be retaken with a mesh model, see that file), how they were made, and the checks each image must pass. Nothing is uploaded; App Store Connect holds 0 of 10 screenshots.
- [app-store-connect-worksheet.md](app-store-connect-worksheet.md): the field-by-field App Store Connect answers, with what was observed there on 2026-10-12.
- `screenshots/` and `app-preview/`: the images and the candidate videos.

The review notes live in [../app-store-submission.md](../app-store-submission.md). Claims in the listing were checked against `docs/validation/host-matrix.json`, the format catalog and the entitlement files; the claim table in the listing file maps each claim to its catalog IDs and its recorded evidence. The matrix records the Finder preview for 4 of 74 types, the Quick Look panel for 21 and Finder thumbnails for none, all on development-signed builds (the counts were 4, 23 and 0 of 76 before the two CAD entries left the catalog on 2026-10-13).

Decisions that were open and are now taken: languages (English U.S. and U.K. at launch; the other 13 translations stay drafts until reviewed) category (Utilities primary, Developer Tools secondary), and whether STEP and IGES ship (they do not in 1.0: decision 028, 2026-10-13, closing decision 027 D20 for 1.0). Still open: which Finder types are observed on a store-signed install, the exact System Settings path per macOS version, and the minimum macOS version in practice (the owner reports the app works on macOS 15; no session has recorded an observation).
