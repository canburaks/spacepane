# Task 6 — Decision synthesis and plan handoff

Date: 2026-10-03. Status: synthesis complete. The authoritative implementation checklist is [PLAN.md](../../PLAN.md). This report records how the five research reports were reconciled; it is not a second implementation checklist.

## Inputs reviewed

| Task | Report | Accepted contribution |
|---|---|---|
| 1 | [macOS APIs](01-macos-apis.md) | Modern extensions, exact type declarations, sandbox/App Groups, file-access and host lifecycle boundaries |
| 2 | [Format ecosystem](02-format-ecosystem.md) | Complete 116-row disposition, primary-source evidence levels, reusable adapters, licensing/private-API constraints |
| 3 | [Apple HIG](03-apple-hig.md) | Native companion versus host-owned preview surfaces, relevant keyboard/menu behavior, accessibility and attention |
| 4 | [Technology stack](04-technology-stack.md) | SwiftUI/AppKit hybrid, shared package boundaries, parser shortlist, explicit concurrency and measurable budgets |
| 5 | [UI/UX](05-ui-ux.md) | Setup/status vocabulary, Settings/live samples, per-format interactions, concealment and unavailable-content states |

All five reports were read before the root implementation plan was generated. Current primary-source claims were checked across the reports, including Apple's exact UTI matching rule, the removal path for legacy generators, SQLite WAL/immutable semantics, current ProvisionQL and QuickLookVideo architecture, wrapper-versus-upstream licensing, and the private CoreUI implementation path in AssetCatalogTinkerer. Catalog rows with inaccessible evidence remain qualified rather than silently accepted.

## Decisions and reasons

Later user refinements are incorporated in [modular format extensibility](../decisions/001-format-extensibility.md) and [file-type controls](../decisions/002-file-type-controls.md). Modularity is the primary architectural requirement: adding a normal format should change its adapter, catalog registration and fixtures without rewriting hosts or orchestration. Each shipped logical type also gains a persistent user toggle through the same catalog. Shared parsers do not couple type choices, and disabling a type gates Prev's decoding without promising another macOS provider takes over. These are accepted requirements; implementation remains unchecked in the root plan.

| Decision | Rationale and consequence |
|---|---|
| Native hybrid, not an all-web runtime | SwiftUI provides native setup/settings; AppKit supplies rich text and dense data controls. This offers requested customization without making every preview start a web renderer. Performance remains a benchmark question. |
| Xcode packaging plus SwiftPM libraries | The product needs embedded signed extension targets and entitlements. Shared parsing libraries remain independently testable. A package build alone cannot validate Finder integration. |
| Exact static type manifest and direct companion fallback | Rendering support and provider selection are distinct. Avoid universal fallback promises; explicitly opened files can use the shared pipeline even when Finder chooses another provider. |
| One versioned preferences source with one writer | Atomic App Group snapshots avoid inconsistent theme/settings combinations. Group defaults are reserved for independent simple flags, not competing copies of the same preference. The app can quit. |
| Native Markdown first, measured alternative later | Parsing Markdown is separate from rendering it. Test selection, tables, accessibility and startup cost before choosing a web view. If adopted, it needs resource blocking and sanitization as well as navigation controls. |
| Read-only includes database sidecars | User-visible read-only SQL is not sufficient. Opening or closing a connection must not create/write/delete/checkpoint source-adjacent WAL/SHM/journal files. A snapshot is acceptable only after coherent, authorized acquisition is proven. |
| XIP needs composite inner-file support | An outer XAR table can contain only Metadata and Content. Inner-file listing requires bounded PBZX/CPIO scanning; archive support must not be inferred from XAR capability alone. Signature verification remains out of scope. |
| Privacy is a shared output policy | Masked UI with raw clipboard, source fallback, accessibility or thumbnail output would violate the intended behavior. Request-local Reveal never changes thumbnail output. Heuristics are described honestly. |
| Missing-format coverage and missing-content recovery are distinct | Add useful adapters for existing bytes and informative states for unavailable bytes. Do not promise deleted-file reconstruction, stale content history, or system-wide interception. |
| Full baseline remains explicit | A text-first alpha reduces implementation risk but is not full QuickLook Pro parity. SQLite, archives/folders, XIP and MIDI remain visible completion gates. |
| Specialized formats remain optional decisions | The 116 projects contain many historical or narrow formats. Reuse proven adapters for valuable additions before importing heavy scientific/media/decompiler stacks. |

## Conflicts and overclaims resolved

- **Supplied skill absolutes versus Apple HIG:** keyboard access matters, but every control does not need a unique shortcut or context menu. Read-only tables never gain Delete commands just because a generic checklist mentions deletion. User-adjustable document font sizes coexist with native semantic UI fonts.
- **Old project descriptions versus current sources:** ProvisionQL now has modern extension targets; Marginal's QuickLookVideo now describes Media Extensions/Spotlight. Syntax Highlight's current minimum differs from the supplied older description. The catalog retains these corrections and separate owners of similarly named projects.
- **Licensing shorthand versus actual reuse:** a wrapper's MIT license does not grant blanket rights to its upstream renderer; a permissive license does not validate private APIs. All dependency revisions, notices and transitive assets remain integration gates. No third-party source was copied into an app.
- **“No extraction” versus computation:** a compressed archive can require substantial decompression even to list paths. Added cumulative compressed-read, decoded-scan, directory and metadata byte caps, plus one-entry decompression-bomb tests. Entry counts and UI timers alone are insufficient.
- **“Read-only” versus side effects:** strengthened SQLite acceptance to cover source files, adjacent sidecars, directory changes, filesystem writes and displayed consistency. `immutable=1` is not a workaround for mutable inputs.
- **“Instant customization” versus host caches:** only the in-app sample promises immediate updates as a target. New requests read complete snapshots; existing Finder views and thumbnails may retain earlier output.
- **Local processing versus file-provider behavior:** Prev should neither upload content nor initiate document-triggered network fetches. macOS/cloud providers may independently materialize a file; the product must not promise zero system network activity.
- **API documentation versus measured implementation:** no runtime performance, provider priority, arbitrary-file access, App Store approval or extension status-detection guarantee is inferred from a class existing.

## Release strategy

The root plan defines M0 platform proof, M1 shared pipeline/shell, M2 text/data/customization, M3 complete baseline, M4 prioritized additions, M5 hardening, and M6 later App Store preparation. This ordering places Finder/sandbox uncertainty before broad format investment and carries privacy/accessibility through every renderer.

The initial additions are diff/XML/plist/localization/OPML, followed by notebooks, subtitles, snippets, NFO and CSV/TSV. Certificates, app archives, ebooks/art-container images, offline geospatial views and extra archives follow once their shared readers exist. Scientific arrays, codecs, fonts and 3D/CAD need separate demand and feasibility decisions. These priorities are product recommendations, not a claim that every file format in the source list will be implemented.

## Evidence limits and validation status

Research used primary Apple documentation/support/HIG, upstream implementation repositories, and vendor/author pages. The ecosystem report records 94 GitHub-evidence rows, 8 vendor/author-evidence rows, 13 unavailable/incomplete-evidence rows, and one table-only row. Neither a README nor a license label is a substitute for a build, security audit, compatibility test or legal review of a selected artifact.

The workspace began empty. Local inspection found Command Line Tools selected, Swift reporting 6.4, and no Xcode-named application in `/Applications`; a full Xcode installation elsewhere was not ruled out. No application, Swift package, signed bundle, fixtures, automated application tests or runtime benchmarks were created in this research task.

A targeted Nowledge memory search and health check were attempted; the configured local service refused the connection. No prior-project memory was retrieved or incorporated, and no durable memory save is claimed. The decisions are preserved in these repository documents so future work can proceed without that service.

Completed documentation validation includes report/inventory coverage, local-link and checkbox checks, cross-report terminology and constraint review, and an adversarial technical review that identified the archive-scan and SQLite-sidecar gaps corrected above. Full runtime, signing, Finder and App Store gates remain unchecked in PLAN.md.

- [x] Collect and read the five reports.
- [x] Select the architecture and reconcile scope/evidence boundaries.
- [x] Incorporate critical technical review corrections.
- [x] Write the root checkbox implementation plan and repository guidance.
- [x] Record change history and validate the documentation deliverables.
