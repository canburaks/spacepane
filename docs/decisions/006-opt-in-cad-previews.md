# Opt-in IGES and STEP previews

Date: 2026-10-04. Status: implemented; host and release evidence is recorded separately.

## Product and performance decision

IGES (`.igs`, `.iges`) and STEP (`.step`, `.stp`) are independent catalog formats and default off. This is the user's explicit performance requirement. Their time/memory cost is materially higher than ordinary source previews. New installs, historical preference snapshots and Reset preserve the opt-in boundary. Enable All intentionally enables current CAD formats; a subsequently added opt-in format remains off. A display-name change does not change these stable identities.

Disabled files are classified before any source read or adapter construction. CAD kernel code is not linked into the host, preview extension or thumbnail extension. The host constructs a lightweight registration; the helper starts only for an enabled CAD request. A Metal device is requested only while displaying geometry. Thumbnails remain generic and never import geometry. Bundled helpers add installation size even when the feature is off.

## Smallest justified shared-contract change

`PreviewOutcome.geometryReady(GeometryPresentation)` adds a presentation capability alongside the existing text outcome. `GeometryFormatAdapter` accepts bounded bytes and returns immutable numeric geometry. It knows neither AppKit/Metal nor OCCT types. The pipeline chooses a registration's optional budget only when callers have not supplied their own budget, then enforces the mesh's output cost itself. Existing formats retain their existing budgets, adapters and privacy filtering.

`PreviewMesh` validates bounded vertex/index/face counts, finite normalized coordinates, normals, index topology and physical bounds. `GeometryPresentation` has request identity so view comparison does not repeatedly traverse geometry. Another geometry format normally needs its adapter, registration, catalog entry and fixtures; hosts do not dispatch by CAD suffix.

## Containment and file access

`PreviewCADFormats` launches the bundled, signed `CADWorker` using public Darwin `posix_spawn`, feeds source bytes over stdin and accepts a versioned little-endian numeric protocol from stdout. It discards diagnostics, strips the inherited environment and never passes the source path. No document labels, metadata, textures or external references cross the boundary. This omits metadata; it cannot conceal secrets physically modeled as geometry, so the localized viewer notice states that geometry is shown as stored.

The parent owns nonblocking pipes, cancellation, a 20-second wall deadline, output limits, child termination and reaping. OCCT's initial parse is not cooperatively interruptible, so merely wrapping it in an async task would not provide equivalent cancellation. Each helper has a 15-second CPU limit and a sampled 512 MiB physical-footprint guard. Sampling can overshoot; this is not a guaranteed peak-memory ceiling. Input is limited to 16 MiB, numeric output to 32 MiB, triangles to 500,000 and faces to 100,000. Native mesh allocation can occur before triangle-count inspection; containment remains essential.

The worker uses only inherited sandbox entitlements, without network access. [Apple documents sandbox inheritance](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox) and [the two required keys](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html). Dynamic file grants are not inherited; stdin intentionally avoids relying on them. Actual Finder-host launch must be observed separately from a CLI or companion test.

### Finder service boundary

Actual Finder testing rejected direct child launch (`EPERM`), even though the signed companion could launch the same inherited-sandbox helper. The preview extension therefore uses an embedded `CADImportService.xpc`, launched through public `NSXPCConnection`; the companion retains its direct child transport. The service has its own App Sandbox with no network, user-file or App Group entitlements. It receives bounded source bytes and returns only the existing numeric protocol or typed numeric failures. Connection invalidation cancels owned work. The service starts only after the same explicit CAD policy gate; thumbnails never connect.

The service identity derives from the stable base bundle identifier in build configuration and is supplied to the extension in its Info dictionary. No runtime plugin discovery, downloaded executable or global launch agent is introduced. The service requires the configured preview-extension signing identity and accepts at most two simultaneous imports without queuing document data. Signed Finder rendering of both formats and the supplied model was observed on the development host; broader platform and physical-input validation remain open in [the validation report](../validation/cad-previews-2026-10-04.md). [Apple’s XPC service documentation](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html) describes public service embedding and independent sandboxing.

## Import and rendering boundaries

The pinned OCCT kernel imports surfaces/solids and tessellates trimmed faces, applies transforms and normalizes physical units to millimetres. Tessellation is approximate visualization, not metrology. External/multifile references, wire-only shapes, failed transferred roots/faces, excessive complexity and invalid geometry are declined. Model contents never execute code. See [dependency audit](../dependencies/occt.md) for the pinned source, static library subset, IGES stdin implementation detail and shipping-license gates.

A composed native MetalKit renderer provides orbit, pan, zoom, fit/reset and front/side/top views. Drawing is demand-driven. Finder uses explicit controller visibility because its remote backing window can report occluded while displayed; the companion retains ordinary window-occlusion cleanup. Hidden/replaced previews release GPU resources; reactivation reuses the immutable safe mesh and camera without source rereads. Appearance changes retain navigation state. Controls, status, errors and accessibility summaries use the owning localization resources; source coordinates are not translated or changed by locale.

The companion remains one tabbed window. Finder owns the Quick Look window and routing; imported type declarations do not establish priority over another provider. CAD thumbnail geometry and additional CAD families are not implied by this change.

## Build and distribution

Run `python3 script/build_cad_worker.py --architecture arm64` (or `x86_64`) before a direct Xcode build. The normal `script/build_and_run.sh` full-build modes prepare the host architecture automatically. The first preparation downloads the pinned official source into ignored `.build/cad`; runtime never downloads code. Universal builds must prepare both architectures. Xcode copies and signs helpers in the app and the preview extension’s independently sandboxed XPC service, and embeds notices; it fails clearly if a required architecture has not been prepared.

App Store release remains gated on dependency-license/relinking review, archive/signature validation, macOS 15 and Intel validation, routing coverage and performance measurements. Development implementation is not a legal-compliance or broad-CAD-support claim.
