# JSON Lines support and grouped choices

Date: 2026-10-03. Status: implemented locally; installed Finder routing remains unverified.

## Format contract

JSON Lines is a separate logical format, `data.json-lines`, with `.jsonl` and `.ndjson` aliases. It reuses the safe source presentation and JSON syntax hint while retaining an independent enablement choice from JSON and plain text. The initial capability validates every record before returning any content; it is not a record browser or a partial recovery view.

Input is UTF-8 without a BOM. Each LF-delimited record must be one valid JSON value; CRLF and an optional terminal newline are accepted. Empty input, blank records and malformed records are declined for the whole file, with no raw-text fallback. Source spelling, duplicate keys and number lexemes remain unchanged except for shared concealment. These choices follow the [JSON Lines format description](https://jsonlines.org/); compressed JSON Lines is not part of this slice. Both suffixes intentionally share this preview policy. The [NDJSON specification](https://github.com/ndjson/ndjson-spec) requires a final newline when serializing and permits documented blank-line skipping when parsing; this preview accepts an unterminated final record and rejects blanks, and does not claim strict serialization validation.

The shared JSON scanner stays inside `PreviewFormats`. It parses absolute byte ranges over one bounded source array, retaining cumulative node accounting across records and absolute sensitive ranges for the existing privacy stage. Depth, bytes, lines and work remain bounded; scans check cancellation/deadlines. No host controller, request orchestration, privacy filter or text renderer selects a JSON Lines parser.

## Necessary shared changes

Two small shared capabilities were justified instead of introducing special cases into orchestration:

1. `DecodedText.hasByteOrderMark` retains encoding provenance that the common decoder previously discarded. JSON Lines can reject BOM input after shared decoding; existing text and JSON behavior is preserved.
2. Catalog entries can declare imported types and optional system aliases. A declared imported canonical type can be constructed in an unregistered CLT process. Optional aliases may be absent on older supported systems; this is not permission to invent arbitrary UTTypes or register all data.

The app and both extensions import `org.jsonlines.jsonl`, conforming to plain text, with both suffixes and the format reference URL. This is an app-selected imported identifier, not a claim that the format project publishes a canonical UTI. The selected host also defines `public.ndjson`; its availability and routing on macOS 15 require separate verification. Known suffixes and exact type matches precede conformance; among related declared ancestors, the most specific wins so generic text cannot bypass the narrower format policy. Incomparable ancestors keep catalog order and require an explicit collision decision before future registration. Neither JSON Lines type is declared to be `public.json`, because multiple records are not one JSON document.

Static extension registration is validated against the catalog. Imported type descriptions resolve through generated `InfoPlist.strings` values taken from the format's existing localization resource. The CLT prototype carries the same import declarations for direct file picking. None of these declarations proves which provider Finder selects.

### Amendment 2026-10-06: other products' identifiers as optional aliases

Two apps can import competing identifiers for one suffix, and macOS then picks one per Mac. On the development host, QuickLookPro's imported `com.quicklookpro.file.jsonl` won `.jsonl` over `org.jsonlines.jsonl`. Finder therefore never asked this app, and turning QuickLookPro's extensions off did not change that. Users switching from QuickLookPro would hit the same thing for every suffix where its identifier wins.

The user decided that catalog entries may also list another product's identifiers as optional aliases. They are matched only by exact type and only for the format whose suffix they describe. They are never canonical, never imported or exported, and never a root type. Because they are optional, a Mac without that product simply skips them. The initial set is the 179 identifiers QuickLookPro 1.1 declares for suffixes already in the catalog, across 16 formats; it was derived by suffix from that app's Info.plist. `validate_project.py` names each permitted namespace in `THIRD_PARTY_ALIAS_PREFIXES` and enforces the rules. A test checks that each alias that loads classifies to its own format. Listing an identifier does not claim it, does not change provider priority, and must be rechecked when that product changes its declarations.

## Group controls

Settings groups are derived from catalog metadata. A native collection checkbox represents all/on, none/off or mixed membership. Apple's [collection Toggle initializer](https://developer.apple.com/documentation/swiftui/toggle/init(sources:ison:label:)) supports this state without a custom checkbox renderer.

Search filters visible rows; a group action still applies to its full catalog membership, including hidden rows. Localized scope guidance states that behavior. Each action publishes one complete snapshot, then persists it through the existing writer. Repeated identical collection bindings are no-ops even if storage is unavailable. Enabling a group changes its current members only: unrelated overrides, appearance and the global default remain intact, so Disable All continues to keep future formats off.

The companion's settings store supports injected temporary storage for model tests. This is a narrow test boundary; production still resolves its App Group/private location through `HostedConfiguration`.

## Validation boundary

See [the continuation validation report](../validation/json-lines-and-controls.md). Source/parser checks, companion model checks, native renderer checks and static registration are distinct evidence. Signed Finder, App Group, macOS 15 runtime, complete accessibility and additional shipping-language checks remain open.
