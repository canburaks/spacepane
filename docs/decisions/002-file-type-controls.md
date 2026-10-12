# Decision 002 — User-controlled file types

Date: 2026-10-03. Status: accepted product and architecture requirement; implementation and runtime validation pending.

## Decision

Users can enable or disable each shipped logical file type in **Settings → File Types**. The choice applies consistently to Prev's Finder preview extension, thumbnail extension and companion previews. It is independent of themes, source/rendered modes and temporary display overrides. [PLAN.md](../../PLAN.md) tracks implementation; [Decision 001](001-format-extensibility.md) defines the modular boundaries.

One stable `FormatID` identifies each independently selectable type. A decoder may serve multiple IDs: JSON and JSONL remain separately selectable. Equivalent suffix aliases such as `.md` and `.markdown` share one Markdown choice and are shown together. Specialized types such as `package.json` have explicit detection precedence; disabling one must not accidentally route it through a broader enabled JSON/text adapter. Ambiguous suffixes require bounded identification and a documented fallback, not an arbitrary settings winner.

Only implemented, shipped capabilities appear as switchable rows. The declarative format catalog supplies their names, aliases, groups and IDs; adding a format must not require writing a custom settings screen. The support catalog can also show limitations and link to **Manage File Types**, without maintaining a second preferences store.

## Controls and persistence

- Search by name or suffix; show labelled individual switches and accessible group controls with mixed state.
- **Enable All Types** and **Disable All Types** explicitly affect the whole catalog, even during search. Group actions affect that named group. If filtered bulk actions are added, label them **Enable Search Results** / **Disable Search Results** and apply only to the displayed matches.
- Store one `defaultEnabled` Boolean and sparse `[FormatID: Bool]` overrides in the existing versioned App Group preferences document. Effective enablement is the explicit override, otherwise the default. There are no persistent group flags or duplicate preview/thumbnail choices in the initial design.
- On first valid setup, the default is enabled. Enable All sets the default to true and clears overrides; Disable All sets it to false and clears overrides. Individual/group changes write the affected overrides, removing redundant ones. New types inherit that global default, so Disable All remains effective across upgrades. Preserve stable IDs and existing choices during migrations; highlight newly added types in the list.
- **Reset File Type Choices** restores the documented initial default and clears overrides. Saving failures remain visible. A missing document on first setup is distinct from a corrupt or unreadable existing document: the latter must not silently re-enable content previews; use a disabled-content fallback until settings can be recovered or explicitly reset.

The companion remains the sole persistent writer. New extension requests load a coherent snapshot with no dependency on a running companion. In-app content updates when its type is disabled and cancels its active request. Existing Finder views and OS-cached thumbnails may retain earlier content; changes are not a guaranteed immediate refresh or secure cache erasure.

## Pipeline enforcement

1. Resolve format identity using catalog metadata and only the bounded probes necessary to distinguish it. Classify against recognized formats before considering enablement; do not remove disabled entries and let generic fallback bypass the choice.
2. Apply the shared format policy before constructing a content parser, decompressing members, querying databases, extracting embedded previews or starting media resources. Minimal authorized classification reads are distinct from content rendering and must remain bounded.
3. If disabled, return a typed `disabledByUser` result. Show a neutral state such as **“Previews for this file type are turned off in Prev.”** Use only safe minimal metadata and a generic thumbnail glyph; do not generate source text, a content summary or an embedded thumbnail. The companion provides **Manage File Types**.
4. If enabled, proceed through the existing bounded, cancellable and privacy-aware pipeline. A future optional nested preview must also check the child format's choice; listing a filename in an enabled container does not itself render that child.

This is a shared policy component in the core, with values owned by the preferences/domain boundary. Adapters do not read settings or implement independent toggle logic. Normal format additions gain policy and UI through their catalog record and shared conformance tests.

## Platform boundary

The switches control **Prev's handling**, not macOS's selected provider. Supported content-type declarations remain static in the signed extension bundle. Apple describes the extension's supported types and system hosting in [WWDC19: What's New in File Management and Quick Look](https://developer.apple.com/videos/play/wwdc2019/719/). No documented provider-handoff guarantee has been established for a disabled type or returned error. Do not rewrite registration at runtime, recursively ask Quick Look to preview the same file, or promise another app takes over.

Use a short Settings footer: **“Choose which file types Prev previews. macOS chooses the Quick Look provider. Changes apply to new previews; existing previews and thumbnails may remain cached.”** System Settings controls enablement of the whole extension separately. Verify the disabled preview and thumbnail behavior in actual Finder hosts during M0.

## Acceptance gates

- [x] Record per-type controls, persistence semantics, shared policy and truthful routing limitations.
- [ ] Implement catalog-driven searchable controls, individual/group/bulk changes, mixed states and reset with keyboard and VoiceOver support.
- [ ] Verify choices survive restart, companion quit, upgrades and schema migration; Disable All keeps newly introduced types off.
- [ ] Prove disabled requests never instantiate content parsers or initialize decoding/playback, including generic fallbacks, shared decoders, aliases and specialized formats.
- [ ] Verify preview, thumbnail and companion consistency, active companion cancellation, corrupt-settings handling and visible save failures.
- [ ] Record actual Finder disabled states and cache behavior without claiming provider handoff or immediate invalidation.
