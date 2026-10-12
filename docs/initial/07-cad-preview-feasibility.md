# CAD previews: IGES and STEP

Recorded 2026-10-04. **Accepted product requirement; geometry import/rendering is
not implemented.** The user supplied an IGES example and explicitly requested STEP
and similar CAD previews. This makes IGES/STEP required scope rather than an optional
CAD demand investigation. Renderer/library choices below remain proposals until the
prototype and dependency gates pass.

## Supplied-file findings

A local, read-only structural inspection found a 4,299,318-byte ASCII IGES file,
with CATIA export metadata and a millimetre unit declaration. It has 53,078 records
of 80 columns: 1 Start, 4 Global, 16,064 Directory, 37,008 Parameter and 1 Terminate
record. The Directory contains 8,032 entity entries, including 2,232 type-126,
288 type-128, 720 type-142 and 720 type-144 entities. OCCT documents these as B-spline
curves/surfaces, curves on surfaces and trimmed surfaces. This calls for correct
surface trimming and tessellation; interpreting the file as a ready-made triangle
mesh would not reconstruct the intended geometry. See the official
[IGES translator guide](https://occt3d.com/dev/doc/overview/html/occt_user_guides__iges.html).

These are structural observations, not proof of a valid solid, successful import,
rendering fidelity or performance. No geometry was imported or visualized. The
sample was not uploaded, copied into the repository or licensed as a redistributable
test asset. Its author/organization/header text must not appear in fixtures, logs or
thumbnails. Keep the supplied model as an optional private acceptance case; build
independent synthetic/licensed fixtures for normal tests.

Spotlight resolved the file to a dynamic type conforming to `public.data` on this
host. This is evidence that installed type declarations/routing need an explicit
test, not a stable identifier to hardcode or proof of a Quick Look handler.

## Required experience

| Logical file type | Aliases | Initial scope |
|---|---|---|
| IGES | `.igs`, `.iges` | Local 3D surface/solid preview, including trimmed curved surfaces |
| STEP | `.step`, `.stp` | Local Part 21 geometric models; test AP203/AP214 and supported AP242 subsets individually |

Both types get independent persistent enablement controls, shared by the companion,
preview extension and thumbnails. IGES and STEP aliases do not become four separate
settings. The model view lives inside Finder's host or the existing Try Preview tab,
with orbit, pan, zoom, fit/reset and useful standard views. Provide keyboard controls,
localized accessible labels, contrast-aware shading and a safe textual summary of
units, bounds and partial/unsupported geometry. Approximate mesh bounds are not
certified engineering measurements. Expose incompleteness instead of silently
omitting failed faces or external components.

Do not claim the app displays native CATIA/SolidWorks/Parasolid files because it can
read exchange files exported by those products. STL/OBJ and other mesh formats may
reuse the eventual mesh presentation, but remain separately evaluated additions.

## Proposed implementation boundary

The current source pipeline is not a CAD renderer. `PresentationCapability` only
contains `.text`; adapters return `ParsedTextDocument`; `PreviewOutcome.ready` wraps
`TextPresentation`. The standard input cap in code is 1,048,576 bytes, below the
sample size. The plan's existing text targets do not change that runtime limit.

Introduce a focused geometry capability and an immutable, Sendable safe mesh payload
alongside text, with bounded positions, normals, indices, transforms and validated
numeric metadata. Keep vendor types and GPU/UI objects out of domain contracts. A
dependency-heavy CAD adapter module can own an internal C/C++ bridge; parsers, mesh
validation, orchestration and rendering stay separate. The host renders a capability
and never switches on `.igs`/`.step`. Existing text and MIDI behavior must retain
regression coverage through the necessary shared-contract migration.

Open CASCADE Technology is the leading importer candidate: its
[IGES reader](https://occt3d.com/dev/doc/refman/html/class_i_g_e_s_control___reader.html)
and [STEP reader](https://occt3d.com/dev/doc/refman/html/class_s_t_e_p_control___reader.html)
translate geometry; [BRepMesh_IncrementalMesh](https://occt3d.com/dev/doc/refman/html/class_b_rep_mesh___incremental_mesh.html)
creates tessellation. Use a bounded byte/stream input under the existing authorized
reader, not an importer reopening arbitrary source paths. Catch C++ failures inside
the bridge. Normalize units/transforms and validate finite coordinates, index ranges,
face orientation and output sizes before publishing a mesh.

`ReadStream` alone is not proof that external references cannot be resolved. The
official [XDE STEP reader implementation](https://github.com/Open-Cascade-SAS/OCCT/blob/master/src/DataExchange/TKDESTEP/STEPCAFControl/STEPCAFControl_Reader.cxx)
contains external-file resolution. Audit the pinned reader's actual behavior and
reject unsupported external dependencies; do not adopt a richer metadata/assembly
reader without that boundary. Prefer a narrow presentation sum wrapping existing
text results and a new geometry result so unrelated format adapters need not change.
Include bounded line primitives only if curve-only models enter the tested scope.

Integration must also update package/Xcode product validation and native link staging,
which currently assume the existing local products. Add generalized suspension and
GPU disposal on preview replacement, tab hiding and host teardown. Preserve camera
state on appearance-only changes without reparsing or comparing entire meshes on
every UI update.

Evaluate [MetalKit's MTKView](https://developer.apple.com/documentation/metalkit/mtkview)
for a small native viewer with explicit GPU resource control and
[RealityKit mesh resources](https://developer.apple.com/documentation/realitykit/meshresource)
as an alternative. Neither is the STEP/IGES parsing layer. Choose after the macOS 15
companion/Quick Look prototype demonstrates lifecycle, memory and interaction needs.
There is no requirement for cloud conversion, document scripts, web content or an
external CAD application at runtime.

## Gates before enabling automatic CAD previews

1. **Dependency:** pin a concrete OCCT revision/build, audit its transitive components,
   public extension-safe APIs, architectures, size and notices. The
   [official license](https://occt3d.com/dev/doc/overview/html/occt_public_license.html)
   is LGPL 2.1 with an additional exception. The published exception concerns header
   material; it is not blanket permission to ignore library distribution/relinking
   obligations. Verify the intended App Store packaging route before selecting a
   linking/distribution design; no claim of Store approval or license compliance yet.
2. **Cancellation and containment:** transfer/meshing offer progress hooks, but initial
   file/stream reading does not expose the same interruptible interface. A Swift Task
   timeout cannot terminate a noncooperative C++ call. The current serialized worker
   must not become permanently occupied by an obsolete CAD request. Prove safe
   cancellation or a supported sandboxed containment mechanism before automatic use.
3. **Budgets:** add CAD-specific input, entity, transfer, face, triangle, vertex,
   CPU/GPU-byte and work allowances. Do not raise global text limits. A bounded final
   mesh does not bound the kernel's earlier allocations. Measure against the supplied
   multi-megabyte case and hostile synthetic cases before choosing shipping limits.
4. **References and privacy:** disable external file/material/texture resolution;
   allow no sibling traversal or remote fetch. Omit author, organization, comments,
   embedded annotations and arbitrary part labels initially. Extend privacy handling
   explicitly to geometry metadata; text redaction cannot sanitize a 3D model or
   lettering modeled as geometry.
5. **Thumbnails:** retain generic thumbnails initially. A geometry thumbnail can
   disclose the model itself and needs a separate content/privacy policy, smaller
   work/pixel budgets and actual provider validation. Never smuggle geometry into
   the existing generic-thumbnail contract.
6. **Acceptance:** render the private IGES sample and synthetic STEP/IGES fixtures;
   test trimming, units, transforms, degenerate/nonfinite geometry, malformed input,
   partial assemblies, cancellation/replacement, disabled types, missing bytes and
   source hashes. Verify both hosts, all localized controls, GPU teardown, actual
   Finder routing and macOS 15. Successful header inspection is not CAD support.

The [STEP guide](https://occt3d.com/dev/doc/overview/html/occt_user_guides__step.html)
documents differing protocol coverage and richer XDE metadata/assembly facilities.
Treat AP242, colors, hierarchy and external assemblies as tested capability subsets,
not an unconditional claim derived from the suffix.
