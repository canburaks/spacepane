# 018 — Columnar, scientific, web-capture and geographic data

Date: 2026-10-05. Status: implemented locally with package, renderer and pipeline tests; Finder routing, thumbnails,
VoiceOver and native-speaker review are unverified. Evidence is in
[the validation record](../validation/data-2026-10-05.md). Part of the
[competitor parity program](025-competitor-parity-program.md); the market gaps are Parquet, Avro, Arrow/Feather,
NumPy, HAR, GeoJSON/GPX/KML and richer SQLite schema inspection (Super Quick Look, Quick Data Insights, Python Data
Viewer, Fast SQLite Viewer, JSON Loupe, GPX Preview). All implementations are original and use only system
frameworks; the formats were read from their public specifications.

## Scope

| Format ID | Canonical type | Suffixes | Input path | Safe modes (initial first) | Thumbnail |
|---|---|---|---|---|---|
| `data.parquet` | `org.apache.parquet` (imported) | `parquet` | random access | Rows (when decodable), Table (schema), Summary, Source | content |
| `data.avro` | imported `…type.avro` | `avro` | random access | Table (records), Summary, Source | content |
| `data.arrow` | imported `…type.arrow` | `arrow`, `feather`, `arrows` | random access | Table (schema), Summary, Source | content |
| `data.numpy` | imported `…type.numpy` | `npy` | random access | Table (values), Summary, Source | content |
| `data.numpy-archive` | imported `…type.numpy-archive` | `npz` | random access | Table (first array), Summary, Source | content |
| `data.har` | imported `…type.har` | `har` | bounded bytes | Table (requests), Summary, Source | generic |
| `data.geojson` | imported `…type.geojson` + optional `public.geojson` | `geojson` | bounded bytes | Plot, Summary, Source | generic |
| `data.gpx` | imported `com.topografix.gpx` | `gpx` | bounded bytes | Plot, Summary, Source | generic |
| `data.kml` | imported `…type.kml`, `…type.kmz` | `kml`, `kmz` | bounded bytes | Plot, Summary, Source | generic |

All nine are catalog entries in the `structured` group and are independently switchable like every other type. Their
types are imported declarations (the catalog's established pattern): none claims `public.data`, `public.item` or
`public.content`, nothing is exported, and a system declaration (`public.geojson`, `org.apache.parquet`,
`com.topografix.gpx` on some systems) wins when present. Whether Finder routes these files to this extension is not
claimed. Thumbnail policy `content` means the thumbnail extension may draw a concealed excerpt when the user allows
content thumbnails; the thumbnails workstream owns that drawing. HAR stays `generic` because request lists are not a
meaningful picture; geographic files stay `generic` because a text excerpt of a summary is not meaningful and a track
outline is location data.

## One summary envelope

Every adapter writes one JSON document through the shared `SummaryWriter`, so concealment ranges, escaping, node and
output budgets are the existing ones, and Source, Summary and copy work unchanged. Two optional members add
presentations, declared once in `PreviewContracts/DataSummarySchema.swift`:

- `table` (and, for Parquet, a second `rowSample` of the same shape): `{columns|columnNames, rows, truncated}`. `columns` holds technical identifiers the view translates when it
  knows them (Parquet `repetition`, HAR `method`); `columnNames` holds document names (Avro field names) that are
  always shown verbatim. A cell is a string, `null`, an array of strings (joined: a URL whose query values are
  placeholders) or `{"bytes": n}` for binary content, which only ever appears as a localized length.
- `plot`: coded coordinate chunks (`longitude,latitude` pairs, five decimals, at most 400 per string) as `paths`
  (each a list of chunks) and `points`, plus `simplified`.

The renderers derive the Table and Plot modes from the **concealed** text with the existing bounded outline parser
(`SafeDataPresentation`), never from source bytes. A concealed coordinate chunk is dropped whole; a column whose name
looks secret is already `••••` in every row.
`DataSummaryPaths` lists, per format and parent path, the names a summary may use. The renderers' label sets are built
from it, so only declared names are translated (a Parquet metadata key called `rowCount` stays `rowCount`), and a test
proves every key an adapter writes is declared. The outline view limits shaped the caps: at most 20,000 nodes and
256 Ki UTF-16 units per document, so each builder stops adding rows by an estimated byte budget as well as a row count.

## Shared decoders (all bounded and cancellable, written for this repository)

- `DataJSONReader`: a strict cursor over bytes (RFC 8259 grammar, depth from `maxJSONDepth`, work checkpoints). HAR and
  GeoJSON walk only the members they need and skip the rest undecoded, so the 20,000-node output budget never limits
  input. A UTF-8 BOM is ignored; lone surrogate escapes become U+FFFD; clipped strings never split a scalar.
- `SnappyDecoder`: the raw Snappy block format; the declared length is checked against the caller's maximum before
  allocation (the reservation is bounded by the input size), every literal and copy is bounds-checked, overlapping copies
  repeat bytes, and trailing bytes or a short result are malformed.
- `ThriftCompactReader`: ten-byte varints with an overflow check, zigzag integers, field deltas and long-form ids,
  list/map headers whose counts must fit the remaining bytes, depth 24, skipping of unknown fields.
- `FlatBuffersReader`: bounds-checked vtable/field/vector/string access. FlatBuffers offsets are unsigned and forward,
  so cycles cannot occur; shared subtrees can, and the Arrow schema walk stops at 5,000 fields and depth 16.
- `AvroSchema` (named types resolved by full name, recursion by lookup, depth 32) and `AvroValueDecoder` (zigzag
  longs, strings, unions, enums, fixed, records, arrays and maps in blocks including negative counts, depth 24, a work
  allowance of four steps per block byte so zero-width values cannot spin).
- `NumPyLiteralParser`: a recursive-descent reader of the header dictionary. Names, calls, operators and comments are
  errors; nothing is evaluated.
- `GeoXML`: `XMLParser` with external entities disabled and no DTD loading. Any `<!ENTITY` declaration is rejected
  before parsing (neither GPX nor KML needs one, and entity expansion is the amplification vector); element depth uses
  `maxJSONDepth`; the parse is aborted on cancellation or deadline.

## Format contracts

**Parquet.** Reads the head magic, the tail (length and `PAR1`) and the footer through the bounded random-access
source, so a multi-gigabyte file costs its footer. Shows version, creator, row/row-group/column counts, the schema as a
flattened table (dotted path, repetition, physical/converted/logical type with decimals, time units and integer widths),
the first 6 row groups with the first 30 column chunks each (codec, encodings, sizes, value and null counts) and up to
50 key/value metadata pairs (values clipped, concealed when the key looks secret). `PARE` (encrypted footer) fails as
`encryptedContent`. **Rows (additive):** the first 100 rows of the first row group are decoded from the leading data pages
of up to 20 columns, in a second table opened first as the Rows mode. Supported: columns without repeated ancestors,
PLAIN values and dictionary pages (PLAIN_DICTIONARY / RLE_DICTIONARY indices), data page versions 1 and 2, the
UNCOMPRESSED, SNAPPY (own decoder) and GZIP codecs, nulls through definition levels, and display conversions for
strings, DATE, DECIMAL, unsigned integers, TIMESTAMP (millis/micros/nanos) and legacy INT96. A column with anything else
(delta encodings, other codecs, nested repetition, an unreadable page) is left out and the table is marked truncated; a
failure while sampling never loses the footer summary. Reads are clamped to each chunk's recorded range and to half the
input budget, so sampling cannot turn an accepted file into `inputTooLarge`. Statistics values and the rest of the file
are never read; binary columns show only their length.
**Avro.** Object container files: metadata map, schema (shown as a bounded type tree), codec `null` and `deflate`,
record count by hopping block headers (at most 1,024 blocks, then `partial`), and the first 100 records of a top-level
record schema as a table (40 columns). Codecs `null`, `deflate` and `snappy` (own decoder; the trailing big-endian CRC-32
is verified) decode; other codecs keep the schema and counts and show no rows. Nested values appear as compact
JSON-like cell text; binary values appear as lengths.
**Arrow IPC.** File (`ARROW1`, footer) and stream formats: schema with nested children and dictionary encodings
(flattened table), custom metadata, batch and dictionary counts and row totals (64 file batches, 1,024 stream messages,
then `partial`). Column buffers are never read. Feather v1 (`FEA1`) is refused as unsupported.
**NumPy.** Header versions 1–3, dtype, shape and storage order; a values table for 0-, 1- and 2-D arrays of bool,
integer, float (including binary16) and complex (100 × 20 values), printed exactly with the shortest round-trip
spelling and no locale. Only the bytes of the shown cells are read. `object` dtype (pickle) and structured records are
described and never read. **`.npz`:** the shared ZIP reader lists up to 100 `.npy` members; headers come from the first
bytes of stored members or a capped prefix inflation of deflated ones (never a full expansion); the first printable
array whose archive name does not look secret provides the table. Members are not CRC-checked because only their
beginnings are read.
**HAR.** `log.creator`, `log.browser`, page and entry counts and the first 300 requests: method, scheme + host + path,
status, MIME type (parameters dropped), body size and time. Headers, cookies, post data, response bodies and every
other member are skipped. URL credentials and fragments are dropped; every query value is replaced by a concealed
placeholder, so the value never enters the document (parameter names stay, written as separate parts so the shared
assignment heuristic does not also conceal the host and path before a secret-looking name).
**GeoJSON.** Feature and geometry-type counts, features without geometry, property names (values are skipped), extent,
coordinate counts and a plot. Positions outside longitude ±180 / latitude ±90 are counted and ignored, never clamped.
**GPX.** Waypoint, route, track and segment counts, extent, total track distance (haversine along consecutive points of
each segment, never across segments), elevation range, time span (a small ISO 8601 parser) and the first 20 names.
**KML.** Placemark and folder counts, geometry counts, extent, line and `gx:Track` length, altitude range, time span from
`when`/`begin`/`end`, names, and a plot. `NetworkLink`, styles, descriptions and every reference are ignored. A KMZ
package (`PK` signature) is opened through the shared bounded ZIP reader: `doc.kml`, else the first root-level `.kml`,
is read CRC-checked into memory within the input budget (its declared size is checked first, so a compressed bomb is
refused) and parsed; icons, images and all other members are ignored and nothing is extracted. Distances and elevations are integers with locale grouping through the existing count-field
formatting; times are ISO 8601 text.

## The Plot mode

`NativePreviewMode.plot` (title `preview.mode.plot`) draws paths and points in an equirectangular projection (longitude
scaled by cos of the mid latitude, uniform fit, centered), with the preview palette, no map tiles and no network.
The drawing is one accessible image with a localized label (path and point counts), the longitude/latitude extent as its
value and caption, and help text; a notice appears when long paths were thinned. Adapters keep at most 250,000
positions in memory and write at most 4,000 (uniform thinning that keeps every path's endpoints, 500 paths); the view
accepts at most 8,000.

## SQLite schema grid

The summary keeps its existing content and gains a `table` envelope member: one row per ordinary-table column with
declared type, NOT NULL, default, primary-key position, foreign-key target and the indexes using it. It comes from
`PRAGMA table_xinfo`, `foreign_key_list`, `index_list` and `index_xinfo` run on the existing private, read-only,
`query_only` snapshot. **The authorizer now admits `SQLITE_PRAGMA` for exactly those four names** (a unit test pins the
set); every other pragma and action stays denied, and virtual tables are never introspected (the existing detection,
`SQLITE_PREPARE_NO_VTAB` and `trusted_schema=OFF` apply). Defaults of columns or tables whose names look secret, and
defaults that contain a secret-looking assignment, are concealed; the existing no-write, sidecar, lock, statement
deadline and row/cell limits are unchanged, and a failure while building the grid (other than cancellation or the
deadline) omits the grid instead of losing the preview. Summary stays SQLite's first mode. A table picker over
multiple tables is not implemented.

## Privacy

Likely secrets are concealed in every representation. Every cell, key and value passes through `SummaryWriter` (assignment
heuristic) and the shared filter's value patterns. Adapters add: whole columns whose Avro field name is sensitive;
nested Avro values containing a secret-looking key; Parquet/Arrow/Avro metadata values under sensitive keys; NumPy
archive arrays whose names look secret contribute no values; HAR never reads headers, cookies, bodies or query values;
GeoJSON never reads property values; XML adapters ignore extensions and descriptions. Binary values (`bytes`, `fixed`)
are shown only as lengths. Images are not extracted. No new representation of source bytes is exposed.

## Security and limits

All input is bounded before allocation by `PreviewBudget`: random-access reads are charged cumulatively; Avro blocks,
decompressed output (eight times the input budget, at most 16 MiB), headers (half the budget, at most 4 MiB) and NumPy
headers (64 KiB) have explicit caps; strings, keys and cells are clipped at character boundaries. Every loop calls
`context.checkpoint()` at intervals, and every adapter's first statement is a checkpoint (the shared cancellation and
deadline tests cover all nine). Adapters never write or extract, never open siblings, never load references, never
evaluate document content and fail with typed `PreviewFailure` values. Truncation and corruption sweeps over every
fixture assert that only typed failures occur. Input over the budget is `inputTooLarge`: the default 1 MiB limits HAR,
GeoJSON, GPX and KML documents, which are read whole; Parquet, Avro, Arrow and NumPy read only what they need.

## Localization

107 new keys (`preview.data.*`, `preview.mode.plot`, 18 format names and descriptions; the KML entry's two keys were revised when KMZ was added) in all 14 languages as drafts
pending native-speaker review. Field and column labels are app-owned; Avro field names, Parquet column paths, metadata
keys, GeoJSON property names, geometry type names, Arrow and NumPy type spellings and every file value are never
translated. Numbers in tables are exact text; counts in summaries use locale grouping. The Source word inside the plot
notice matches `preview.mode.source` in each language.

## Shared-contract edits

Marker insertions only: catalog entries after `data.tsv`; `TextAdapter.swift` registrations; `SafePreviewModes.swift`
(cases `plot` and `rows`, titles, models, availability, initial mode, derivation); `SafeModeContentView.swift` (the Plot and
Rows views; Rows reuses `preview.summary.rows` as its title and hosts the shared native table);
`SafeSchemaLabels.swift` (nine sets); `PreviewStrings.swift` keys; the appearance-sample and host-fixture generators. New
contract files: `DataFormatIDs`, `DataSummarySchema`, `DataSummaryPaths`. `tools/test_localization.py` lists the three
formatted keys the validator discovers. No pipeline, privacy-filter or host-controller code changed.
`SQLiteInspectionAdapter` (owned by this workstream) gained the grid and the authorizer change above. No new library is
linked: zlib (already used by the ZIP reader), Compression and Foundation `XMLParser` are system frameworks.

## Known limits and not promised

- No table picker for SQLite. Avro `bzip2`, `xz` and `zstandard` codecs, Parquet ZSTD/LZ4/Brotli/LZO pages, delta and
  byte-stream-split encodings, nested (repeated) Parquet columns, TCX, Feather v1 and Arrow compressed buffers are not
  decoded; those columns or files show their structure without values.
- The SQLite summary's new `table` member is labelled by the data label sets only for the nine new formats. The
  existing `database` label set (in `SafeSchemaLabels+Containers.swift`, owned by the listings workstream) matches
  `database.sqlite` first and does not list `table`, so that one key shows as written until the lead lets the data sets
  also cover SQLite (see the validation record's request).
- Finder routing, thumbnails, VoiceOver, translated layouts and signed-host behavior were not verified.
- Distances use a sphere of radius 6,371,008.8 m (haversine); they are estimates, not survey values. Time spans use the
  file's own timestamps. Longitude wrap at the antimeridian is not handled.
