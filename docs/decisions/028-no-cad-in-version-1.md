# Decision 028: no STEP or IGES in version 1.0

Date: 2026-10-13. Status: decided by the owner on 2026-10-13; the build mechanism is being implemented the same day, so nothing below claims that a build without CAD has been made, archived or observed. Amends [decision 006, opt-in CAD previews](006-opt-in-cad-previews.md) (1.0 ships without those formats) and closes D20 of [decision 027](027-best-in-class-quality-program.md) for 1.0 ("CAD in 1.0: publish the sources with a written offer, or ship 1.0 without STEP and IGES"). It also settles R-2 of the [review readiness plan](../plans/2026-10-12-review-readiness-plan.md).

## Decision

Version 1.0 ships without the STEP and IGES 3D previews. CAD may return in a later version if the licence exception is bought or the licence question is otherwise cleared. No licence was bought and no legal review took place; this decision is a choice of scope, not a finding about the LGPL.

## Background

- STEP (`.step`, `.stp`) and IGES (`.igs`, `.iges`) import uses Open CASCADE Technology (OCCT) 7.9.3 under the GNU LGPL 2.1, statically linked into the helper executable `CADWorker` ([dependency audit](../dependencies/occt.md)).
- The route prepared so far was to publish the helper's source, the build scripts and a written offer in a public repository, https://github.com/canburaks/spacepane-cad-source, and to ship under the LGPL. D20 of decision 027 named it, and `Native/CADWorker/SOURCE-OFFER.md` records it as pending legal review.
- On 2026-10-12 the owner asked Open Cascade whether that route is acceptable for Mac App Store distribution. Their reply, received 2026-10-13, in substance (a summary, not a quotation):
  - The LGPL 2.1 applies however little of OCCT is used and although it sits in a separate helper.
  - The standard Open CASCADE exception covers OCCT header files only. It gives no exception for static linking or for App Store distribution.
  - If the distribution model cannot meet the LGPL requirements, the appropriate option is the limited static-linking exception they had quoted. It can be scoped to the SpacePane application with its Quick Look extensions and helper, OCCT 7.9.x, and Mac App Store and TestFlight distribution. Maintenance terms are separate and would be in a proposal.
  - They did not say whether the source-offer route satisfies the LGPL.
- The owner then decided to cut STEP and IGES from 1.0.

## Build 2 and build 3

Build 1.0.0 (2) was uploaded on 2026-10-12 with CAD in it. It is for the owner's internal TestFlight testing only and must not be submitted. The submission build is build 3, built without CAD. Build 1 was already set aside (uploaded 2026-10-10, never to be submitted).

The public source mirror is not changed and nothing new is pushed to it. Since no build containing the helper was distributed to anyone but the owner, the written offer has not taken effect.

## Mechanism

Described here as decided; the implementation is made by other changes and recorded in the changelog.

- A build setting `PREV_INCLUDE_CAD` in `Configuration/Base.xcconfig` is NO for 1.0. It controls whether the helper `CADWorker`, the XPC service `CADImportService.xpc` and the `OCCT-Notices` folder are in the product, and whether the Swift compilation condition `PREV_INCLUDE_CAD` registers the CAD adapters in the companion and the preview extension.
- The two catalog entries `cad.iges` and `cad.step` are removed from `FormatCatalog.json`. They are kept verbatim in `Configuration/CADFormatCatalogEntries.json`.
- `script/check_release_archive.py` and `script/validate_project.py` enforce the setting.

## What leaves the product

- The `CADWorker` helper (the companion's copy and the service's copy), `CADImportService.xpc`, and the OCCT notices folder.
- The CAD adapters' registration in the companion and the preview extension.
- The catalog entries `cad.iges` and `cad.step`, and with them their File Types rows, their appearance samples, their rows in the host matrix and the product's file-type count: 74 types, not 76. The matrix's Quick Look panel observation of both formats (development-signed build, one Mac) leaves with the rows.

## What stays in the repository

All CAD sources stay, unchanged: `Native/CADWorker`, `Native/CADImportService`, the `PreviewCADFormats` module and its tests, the CAD build and packaging scripts (`script/build_cad_worker.py`, `script/package_cad_source_offer.py`), the CAD entitlements, `ThirdPartyNotices/OCCT/`, `docs/dependencies/occt.md`, [decision 006](006-opt-in-cad-previews.md), [the CAD validation record](../validation/cad-previews-2026-10-04.md) and the feasibility record. The public mirror `canburaks/spacepane-cad-source` stays as it is.

The mesh formats STL, OBJ, PLY and 3MF are native Swift readers ([decision 024](024-mesh-formats.md)), do not use OCCT, are unaffected and keep the 3D viewer.

## Consequences

Store copy ([listing](../release/app-store-listing.md)):

- The description drops "plus STEP and IGES CAD models once you switch them on", the "STEP and IGES previews are off by default" bullet and the closing Open CASCADE paragraph, and says 74 file types. The mesh line stays: "STL, OBJ, PLY and 3MF models you can turn".
- Keywords use the swap row for this case, without `step`, `iges` and `cad`. The localized keyword drafts drop the same terms.
- The description and keywords stored in App Store Connect still carry the CAD wording and must be re-pasted from the listing file before submission. Build 2 in App Store Connect is not the submission build.

Screenshots: the made image `07-models.png` shows a STEP model and must be retaken with a mesh model (for example the generated STL). `08-file-types.png` reads "76 of 76 enabled" and is retaken from build 3. The retakes are open items.

Review notes ([submission worksheet](../release/app-store-submission.md)): the notes name build 3, drop the STEP and IGES paragraph, the two CAD sample files and the source-offer link, and name one mesh sample. The review sample archive no longer holds STEP or IGES files. The worksheet row "Description: open-source line" is not applicable in 1.0.

Website (`spacepane-web`, a separate private repository): its data is synchronised from the catalog and the host matrix, so `npm run data:sync` runs there after the catalog change, and any page that names STEP or IGES as a feature of 1.0 or counts 76 types needs the same correction. The open-source page and its redirects keep working, because the shipped app links to them.

Other records: the open checklist item "resolve the pending legal review wording" is not applicable to 1.0. D27 (a TestFlight round) stays a gate for the rest of the store-signed behaviour, and no longer needs to cover the CAD path for 1.0.

## Bringing CAD back

In order:

1. Settle the licence first. Either the limited static-linking exception (scoped as described in the background) is obtained, or the LGPL route is cleared in a way the owner accepts, or the helper is replaced. Record the outcome; do not infer it from this record.
2. Set `PREV_INCLUDE_CAD` to YES in `Configuration/Base.xcconfig`.
3. Restore the two catalog entries from `Configuration/CADFormatCatalogEntries.json` into `FormatCatalog.json`, then regenerate what the catalog drives: manifests (`script/sync_manifests.py`), appearance samples (`script/generate_appearance_samples.py`) and the host matrix (`docs/validation/host-matrix.json`). Run `npm run data:sync` in `spacepane-web` and commit the result there.
4. Restore the store copy and the samples, from git history before 2026-10-13 or from the text kept here:
   - Description, 3D bullet: `• STL, OBJ, PLY and 3MF models you can turn, plus STEP and IGES CAD models once you switch them on`; the count line becomes 76 again.
   - Description, under GOOD TO KNOW: `• STEP and IGES previews are off by default, because large models take time and memory. Their measurements are approximate.`
   - Description, last paragraph, only if the chosen licence route needs it: `3D previews use Open CASCADE Technology under the GNU LGPL 2.1 with the Open CASCADE exception. The helper's source and the written offer for the library source: https://github.com/canburaks/spacepane-cad-source`
   - Keywords, the earlier line ending `step,iges,stl,cad`; the localized drafts likewise.
   - Review notes: the STEP and IGES paragraph and the two CAD sample files (`32-winch-gear.step`, `33-box.iges`) in `script/build_review_samples.py`, with the "switch on first" step in its README.
   - Screenshot scene 07 with a STEP model, and the File Types page with the CAD rows.
5. Refresh the public source mirror with `script/package_cad_source_offer.py`, tag it for the app build it matches, and push it only on the owner's instruction (`mani run mirror-drift` shows whether it is behind).
6. Validate the store-signed XPC path on TestFlight (decision 027, D27): turn STEP on, preview a model, and read the CAD peer requirement result under the TestFlight and the Mac App Store signatures, as recorded in [the TestFlight runbook](../release/testflight.md).
7. Update decision 006, the dependency audit and the changelog, and remove the pointer at the top of decision 006.
