# Mesh formats: STL, OBJ, PLY and 3MF

Date: 2026-10-05. Status: implemented and unit-tested; Finder routing, signed-host rendering, thumbnails and VoiceOver are not observed. Part of [the competitor parity program](025-competitor-parity-program.md); the evidence is in [the mesh validation record](../validation/mesh-2026-10-05.md).

## Scope

The competitor review found that general-purpose previewers (iPreview, Eyemesh) and specialists (Universal 3D Previewer, mesh-peek, Peek3D, 3MF Viewer, MakersPreview) preview triangle-mesh files. SpacePane already had a neutral validated mesh contract and a native Metal viewer with orbit, pan, zoom and fit, used by the opt-in IGES/STEP importer. This decision adds four formats to that viewer with original pure-Swift readers, without a new presentation, host switch or dependency.

| Format | Stable ID | Suffix | Content type | Encodings read |
|---|---|---|---|---|
| STL | `model.stl` | `.stl` | system `public.standard-tesselated-geometry-format` | binary; ASCII |
| Wavefront OBJ | `model.obj` | `.obj` | system `public.geometry-definition-format` (conforms to `public.text`) | text |
| Polygon File Format | `model.ply` | `.ply` | system `public.polygon-file-format` | `ascii`, `binary_little_endian`, `binary_big_endian` |
| 3D Manufacturing Format | `model.3mf` | `.3mf` | imported `org.webmeister.spacepane.type.3mf` (conforms to `public.data`) | OPC ZIP with XML model parts |

All four are catalog entries in group `media` with presentation `geometry`. 3MF uses thumbnail policy `generic`; STL, OBJ and PLY use `none` (see the thumbnail note below). Their IDs are declared in `PreviewContracts/MeshFormatIDs.swift`; the readers are in `PreviewFormats/Geometry/` and registered by `MeshFormatAdapters.registrations`, which `StandardFormatAdapters` includes, so the companion and the preview extension compose them without per-suffix code. Each format has its own file-type switch and appearance-theme sample.

## Reader rules

Every reader consumes the bounded bytes the pipeline already read. None opens a second file. Input, vertex and triangle ceilings are checked before the allocation they bound; every loop calls `context.checkpoint()`; failures are typed `PreviewFailure` values.

- **STL.** A file is binary when its size equals `84 + 50 * N` for the count `N` in its header, whatever the 80-byte header says; many binary exporters start the header with "solid". Otherwise a leading `solid` selects the ASCII grammar (case-insensitive keywords, several solids, byte order mark, CRLF, ignored facet normals). Anything else, including a truncated or padded binary file, is malformed. Positions are welded by exact value as they are read.
- **OBJ.** `v` and `f` in every reference form (`v`, `v/vt`, `v//vn`, `v/vt/vn`), negative (relative) indices resolved against the vertices defined so far, polygon fan triangulation, backslash line continuations, comments. Texture coordinates, normals, groups, objects, smoothing groups, lines, points and free-form statements are skipped. `mtllib` and `usemtl` are never followed: the reader has no path to a sibling file. Valid geometry without faces is `unsupportedFormat`.
- **PLY.** The header is parsed with fixed ceilings (64 KiB, 4,096 lines, 32 elements, 64 properties each). Vertex `x`, `y`, `z` may be any scalar type; faces come from a `vertex_indices` or `vertex_index` list. Every other element and property is skipped by size (binary) or token (ASCII) without being interpreted, so unused normals or colours need not be valid. Declared row counts must fit in the file before any storage is reserved. A point cloud, or faces without an index list, is `unsupportedFormat`.
- **3MF.** The ZIP is read by the shared `ZIPArchiveReader` (CRC-checked, encrypted members refused). The model part is the target of the `_rels/.rels` relationship whose type ends `/3dmodel`, else `3D/3dmodel.model`, matched case-insensitively. The model XML is read by `XMLParser` with external entities off, **no document type declaration at all** (a byte search refuses any `<!DOCTYPE`, and the delegate aborts on any entity, notation or attribute-list declaration), depth and node ceilings from the budget, and namespace declarations counted as nodes. Objects with meshes, component lists, build items and their 3×4 transforms (specification row-vector convention; component transform then item transform) are composed with bounded recursion (depth 32), cycle detection and an instance ceiling of 100,000. Slicer packages that keep objects in other model parts of the same archive (the production extension's `p:path`) are followed, up to 32 parts and only inside the archive. The `unit` attribute (micron, millimeter, centimeter, inch, foot, meter; default millimeter; anything else is malformed) is applied to every part and converted to millimetres. Support-type objects are not drawn. Colours, materials, textures, thumbnails, slicer settings and unknown extensions are ignored. When the build list is empty, objects that no component uses are drawn.

## Shared mesh preparation

`MeshBuilder` turns indexed triangles into the contract's `PreviewMesh`. It rejects NaN, infinities and coordinates beyond the contract's 1e12 magnitude, rejects out-of-range indices, drops zero-area and repeated-corner triangles (a file with only those is malformed), centers the geometry and scales it to an extent of two, and computes shading normals. A corner shares its vertex's smooth normal only with neighbouring faces within a 45 degree crease angle, so a cube keeps sharp edges and a sphere shades smoothly; above 32 incident faces the work degrades to a comparison with the vertex average so a pathological vertex stays linear. The physical bounds in the mesh are the model's own coordinates in millimetres. The viewer draws two-sided, so winding is not corrected.

## Limits

| Limit | Value | Source |
|---|---|---|
| Input bytes | 16 MiB | `GeometryLimits.maximumInputBytes`; lowered by a caller's budget |
| Output bytes | 32 MiB | `GeometryLimits.maximumSerializedBytes`; lowered by a caller's budget |
| Triangles | 500,000 | `GeometryLimits.maximumIndices / 3`, and never more than `(output budget − 72) / 12` |
| Source vertices | 1,500,000 | `GeometryLimits.maximumVertices` |
| Wall deadline | 10 seconds | `MeshLimits.requestBudget` (the CAD helper's is 20) |
| 3MF decoded XML | 64 MiB across parts, at most 64 times the input budget | `ContainerLimits` |
| 3MF XML nodes | the budget's `maxJSONNodes` (1,000,000 in the mesh budget) | request budget |

The reader registrations carry their own default budget, as the CAD ones do; a caller that supplies a budget (the adversarial corpus passes the 1 MiB standard budget) can only lower these.

## Default enablement

All four formats are **on by default**. The decision follows the measurements (release, Apple M5 Pro): a 100,000-triangle model parses in 6 to 31 ms in every format except 3MF (about 210 ms, almost all of it `XMLParser`), and the largest admitted inputs (a 16 MiB binary STL, a 3MF at the 500,000-triangle ceiling) in about 55 ms and 1.3 s, with a process high-water mark of about 270 MiB for the pair. Debug numbers are 4 to 60 times slower (a 3MF at the ceiling takes about 5.8 s in Debug), which still fits the 10-second deadline here. Work is in process, bounded and cancellable, unlike IGES/STEP, which need an isolated kernel helper and stay off. The existing `CatalogDefaultEnablementHasOneOwnerAndPreservesExistingTypes` test already expects every type except IGES and STEP to default on. Any user can turn each format off independently, and a disabled type never falls back to text: `.obj` is a text file, but its suffix classifies it as the mesh format first, so disabling it shows the disabled state.

## System-provider overlap

Observed 2026-10-05 on macOS 27.2 (26B5091g), by reading the system's own manifests, not by running Quick Look:

- `/System/Library/PrivateFrameworks/Hydra.framework/Plugins/HydraQLPreviewExtension.appex` (`com.apple.HydraQLPreviewExtension`) and `HydraQLThumbnailExtension.appex` declare `public.standard-tesselated-geometry-format`, `public.geometry-definition-format` and `public.polygon-file-format` (STL, OBJ, PLY), together with USD, Alembic and MaterialX. The preview extension sets `QLRequiresExternalResources`, which suggests it reads sibling materials and textures. This host has no `.qlgenerator` that mentions these types.
- `.3mf` has no system type on this host: `UTType(filenameExtension: "3mf")` is a dynamic type, so our imported declaration is the only definition. Nothing observed here competes for 3MF.
- The three system types are Apple's: we declare support for them in `QLSupportedContentTypes` and export nothing. `public.geometry-definition-format` conforms to `public.text`, so OBJ is both a mesh and a text type.

What this means: on a macOS that ships the Hydra extensions, our STL, OBJ and PLY support may compete with Apple's provider, which can show materials and textures that ours deliberately omits. macOS chooses one provider per type; this product does not control that choice and does not promise to win it. Which provider Finder actually uses was not observed (`pluginkit` and Finder were not touched). Whether macOS 15 ships those extensions or a different 3D preview is not verified. The settings workstream's provider-conflict diagnostics are the right place to explain this to users.

**Thumbnails (accepted at integration).** If our thumbnail extension were chosen for STL, OBJ or PLY, Finder would show a content-free glyph where Apple's Hydra thumbnail extension shows a rendering. Those three therefore use `ThumbnailPolicy.none`, so the thumbnail extension does not register them and the system thumbnail stays in place. 3MF has no system type here and keeps the generic glyph.

## Units and status

STL, OBJ and PLY carry no units; their coordinates are taken as millimetres, the 3D-printing convention. 3MF coordinates are converted from the declared unit to millimetres. The contract stores physical bounds in millimetres and nothing about units, and `NativeGeometryPreviewView` always labels its dimensions "mm". So the label is true for 3MF and CAD, and an assumption for STL, OBJ and PLY that the viewer cannot flag. The status line also always shows the CAD privacy notice ("3D geometry is shown as stored. Document metadata is omitted."), which is accurate for meshes. Geometry outcomes do not pass through `TextPresentation`, so `PresentationNotices` cannot add a line. Closing this needs a shared-contract change owned by the lead (see the requests below); no mesh-specific string was added.

The same view reports `faceCount` as "Faces". The contract rejects more than 100,000 faces, so STL and 3MF report `min(triangles, 100,000)`, while OBJ and PLY report their source polygons. Models of 100,001 to 500,000 triangles are displayed and counted correctly in "Triangles"; only the "Faces" figure saturates.

## What is not promised

- Finder routing, preview or thumbnail invocation for any of these types, in any macOS version. Companion parsing and unit tests are not Finder evidence.
- Colours, materials, textures, UV maps, vertex colours, animation, skeletons, units shown for STL/OBJ/PLY, cross-sections or wireframes.
- Non-convex polygon triangulation (fan from the first vertex), OBJ free-form curves and surfaces, PLY triangle strips and point clouds, 3MF beam lattices, slice extension, multi-plate selection, or 3MF `p:path` parts outside the archive.
- Repair of inconsistent winding or non-manifold meshes; the viewer lights two-sided.
- Peak memory below the measured high-water mark, or time on other hardware. A deadline does not preempt native Foundation/libxml2 calls between checkpoints.
- Content thumbnails from the embedded 3MF image; that belongs with the thumbnails workstream and `PreviewImage`.

## Requests for the lead (files this workstream does not own)

1. `GeometryPresentation` / `NativeGeometryPreviewView`: carry a "units are assumed" flag (or the source unit) so STL, OBJ and PLY dimensions are labelled honestly, and show a localized notice for it.
2. `GeometryLimits.maximumFaces`: raise it to the triangle ceiling for mesh sources, or make `faceCount` optional, so "Faces" is not saturated for large STL and 3MF files.
3. `Tests/Integration/AdversarialCorpusChecks.swift`: this branch makes the minimal edit needed for the geometry outcome; carry it through the merge.
4. Consider `thumbnail: none` for the three system-typed formats (see above).
5. Website data (`npm run data:sync`) and the user-facing supported-format list need the four new catalog entries.

## Extensibility check

A fifth mesh format using this viewer needs its reader, one catalog entry, one registration line under `// [mesh]`, localized name and description, a sample and a fixture. The shared contract, pipeline, hosts and renderer are unchanged; the one shared test harness edit above is the first geometry outcome outside the CAD formats.
