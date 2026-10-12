# Decision 001 — Modular file-format support

Date: 2026-10-03. Status: implemented contracts and local JSON Lines extensibility proof; installed-host validation pending.

## Context

The user makes modular design the highest priority and asks that future file types be easy to add. Apply separation of concerns, single responsibility, DRY, KISS, YAGNI, open/closed and dependency inversion wherever practical. The existing research recommends reusable format adapters; this decision makes their boundaries and acceptance criteria explicit.

## Decision

Use small domain contracts, explicit composition and bundled format adapters. Keep platform hosting, request orchestration, file access, format parsing, privacy policy, presentation and settings separate. The concrete module responsibilities are maintained in [PLAN.md](../../PLAN.md#extending-file-support-is-a-first-class-architectural-requirement); [AGENTS.md](../../AGENTS.md) makes these rules part of future development work.

The dependency direction is:

```text
App / extension composition
  ├─ PreviewCore       → PreviewContracts
  ├─ PreviewFormats    → PreviewContracts + selected decoder libraries
  ├─ PreviewRenderers  → PreviewContracts + AppKit/SwiftUI
  └─ PreviewPreferences → stable domain/settings values

PreviewCore must not depend on PreviewFormats or PreviewRenderers.
Concrete format adapters must not depend on a Quick Look host or view.
```

Contracts are owned by the domain, not dictated by a third-party parser's API. The composition boundary injects concrete services and adapter factories. Prefer initializer injection and plain values; do not add a service locator or a general dependency-injection container. Keep actual protocol signatures minimal and validate them against the first real adapters before treating them as stable.

### Distinct responsibilities

- **Descriptor/catalog:** stable format identity, canonical types, aliases, bounded signature requirements, supported presentation/thumbnail capabilities and documented limits. One source of truth feeds or validates runtime metadata, signed manifests and supported-file help.
- **Selection/registry:** deterministic dispatch among registered adapters, including signature collisions and source fallback. A bounded probe refines a received file; it does not change Finder routing. The registry stores lazy factories, not globally initialized parsers.
- **File-type policy:** resolve the stable format ID, then apply shared user enablement before content parser construction. Generate controls from the catalog, not individual adapters; shared decoders do not couple independent type choices. Follow [Decision 002](002-file-type-controls.md), including disabled-type fallback rules.
- **Format adapter:** interpret that format's bytes, wrap any decoder dependency, preserve relevant semantics and report errors/omissions. Related formats can share a parser without becoming the same format.
- **Reader and request context:** provide authorized bounded reads, shared cumulative budgets, cancellation and typed access failures. An adapter gets the capabilities it needs rather than the entire application service graph.
- **Privacy stage:** apply common policy to presentation data and alternate representations. Adapters can identify sensitive fields; they cannot silently bypass the shared policy. Malformed-input and source fallbacks obey it too.
- **Presentation/rendering:** consume immutable safe models and reusable presentation capabilities. A new format using text, an outline or a table should not require a new host screen. Parser-specific vendor objects never reach a view.
- **Host integration:** translate Quick Look callbacks or companion actions into requests, display results, and dispose resources. Host controllers contain no per-suffix parser switches.

Do not force every format into a fully materialized document or one protocol containing all possible operations. Implement focused paging/playback capabilities when SQLite/MIDI work actually needs them; those capabilities must retain request lifetime, read-only, budget and cancellation rules. A new presentation kind can require a deliberate shared-contract change. Open/closed aims to avoid repeated edits to unrelated code, not freeze the domain model forever.

### Reuse without overengineering

Share existing common behavior: encoding, authorized reads, limit accounting, cancellation, redaction, theme application, empty/error states and presentation controls. Do not duplicate these in each adapter or separately for the companion and extensions. Thumbnail rendering may use less data and stricter limits while reusing safe decoding primitives; it must not construct a full interactive preview just for reuse.

Start with one formats target and clear family folders. Isolate a heavy or independently maintained decoder in its own target when the actual dependency, extension-safety or resource requirements justify it. Do not build separate packages for every file suffix, speculative inheritance hierarchies, automatic plugin discovery, downloadable renderers, a public plugin SDK or a stable external ABI.

KISS and YAGNI constrain abstraction growth. A helper stays local until there is real shared behavior or an existing architectural boundary needs it. SRP means a coherent reason to change, not arbitrary file/function size. DRY applies to knowledge and semantics; superficially similar but independently evolving parsers may remain separate.

## Standard workflow for adding a file type

1. Define a small support contract: supported variants, canonical type/aliases, signature collisions, intended presentation, privacy and thumbnail policy, and fallback behavior. Confirm the relevant specification and dependency license.
2. Add the adapter in its format-family module. Reuse bounded readers and an existing presentation where suitable; keep vendor types private to the adapter. Add a new rendering capability only when existing ones cannot express the real requirement cleanly.
3. Add one catalog record and explicit runtime binding. Generate or validate manifest/help/settings metadata from the same source. Detect missing bindings and accidental duplicate IDs; represent intentionally shared types and dispatch precedence explicitly. Reuse the standard file-type switch and stable-ID persistence; no custom toggle UI is needed.
4. Add normal, malformed, oversized, cancellation, disabled-type and privacy fixtures. Run shared adapter contract checks plus format-specific semantic tests and existing-format regressions. A known format's failure or disabled state must not be hidden by an indiscriminate fallback to an unrelated adapter.
5. Verify actual Finder preview and thumbnail routing separately from companion parsing, and record resource/performance and accessibility evidence. Make unsupported variants visible.
6. Update the support matrix, relevant plan checkbox and changelog. Document any core/shared-contract edit and why this format required it.

For an ordinary format using an existing presentation, expected edits are its adapter, catalog/registration and fixtures. Dependency/notices and format-specific preferences may also change when justified. Updating generated manifests is expected; rewriting orchestration, host controllers or unrelated adapters is a design warning to investigate.

## Proof of extensibility

- [x] Record the user's architectural principles and the proposed boundaries in repository guidance and the plan.
- [x] Implement the minimum contracts using real baseline adapters, with an acyclic build dependency graph.
- [x] Add a second real format to an existing presentation without modifying pipeline or host logic; record the changed-file set and any justified exceptions.
- [x] Verify shared contract checks enforce budgets, cancellation, privacy, no source mutation and accurate fallbacks for that adapter.
- [ ] Verify the first adapter and both host paths retain their behavior after the addition.

The second-format exercise is the evidence of extensibility. A large framework or a count of protocols is not.

## First incremental proof

JSON Lines reuses safe text presentation and the existing request/policy/privacy pipeline. Its bounded scanner is shared with the related JSON adapter; unrelated adapters and host controllers are unchanged. The [implementation record](004-json-lines-and-group-controls.md) documents two justified shared capabilities: BOM provenance and catalog imported/optional type metadata, plus a generic specificity fix that prevents generic text from winning over a narrower declared type. Adapter fixtures and existing JSON regressions pass; [90 package tests and four companion model checks](../validation/json-lines-and-controls.md) provide local evidence. Both installed Finder paths remain an open gate.
