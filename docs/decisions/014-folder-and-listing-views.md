# 014 — Folder depth, hidden items and listing views

Date: 2026-10-05. Status: implemented in the listings workstream of the
[competitor parity program](025-competitor-parity-program.md); package tests and typechecks
pass, Finder routing and signed-host behavior are not verified (see
[the validation record](../validation/listings-2026-10-05.md)).

## Gap and scope

Unfold (Native/List/Grid layouts, expandable subfolders, scan depth, hidden items, folder-size
totals), Super Quick Look (expandable hierarchy with counts, dates, kinds, sizes), iPreview
(tree), SpacePeek and FolderPlus (size breakdown, largest items, sorting, search) and
QuickestLook (CSV sticky headers, zebra striping) all show more than SpacePane's JSON-like
outline of immediate children. Those are vendor claims ([landscape](../market/2026-10-05-competitor-landscape.md));
this record covers our own original implementation:

1. The folder summary honors the saved depth (1–4) and hidden-items choice.
2. ZIP listings carry modification dates and list encrypted members.
3. Every listing-shaped summary gains a **Files** table and a **Tree**.
4. Native tables, including CSV/TSV, gain sorting, filtering, striping and a sticky header.

No catalog format, manifest or UTType changed. Settings UI for depth and hidden items belongs
to the settings workstream; this workstream only consumes `RequestContext.options`.

## Folder summary

`FolderSummaryAdapter` opens the authorized directory once; `FolderScan` does the work.

- **Traversal.** Breadth first, so the top level is always complete before a deeper level can
  use up the budget. Each directory is re-opened from the root descriptor one component at a
  time with `openat(…, O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK)`, so a link swapped
  in after a metadata read is refused rather than followed; no path-based call is made below
  the root. Metadata comes from `fstatat(…, AT_SYMLINK_NOFOLLOW)`. No file is opened or read.
- **Links.** A symbolic link is listed as `symlink` and never entered, at any depth. A symlink
  given as the root itself is refused (`unreadableFile`), as before.
- **Packages.** A directory whose suffix marks a Finder package (`.app`, `.bundle`,
  `.framework`, `.plugin`, `.appex`, `.xcarchive`, `.photoslibrary` and others, plus any suffix
  the type database says conforms to `com.apple.package` or `public.bundle`) is listed with
  kind `package`, no size and no item count, and is never entered. Only the *name* is used; asking
  the filesystem for the package bit would need a path-based lookup (the race the descriptor
  walk avoids). A directory merely named like a package but not recognized is an ordinary folder.
- **Filesystems.** A directory on a different device than the root is listed but not entered
  (a mount point can be a blocking network volume) and marks the listing partial.
- **Hidden items.** Hidden means a name starting with `.`. With the choice off they are not
  listed or counted in a folder's `items` and are reported in `hiddenEntries` (names read in
  folders that were listed). The `UF_HIDDEN` flag is deliberately not consulted, so the rule
  is identical for listed folders and for the count-only boundary pass.
- **Depth.** `context.options.folderDepth`, clamped to 1–4 again defensively. Folders exactly at
  the limit are *counted* (names only, no metadata) so every listed folder shows `items`.
- **Order.** Hierarchical pre-order, siblings in natural name order
  (`localizedStandardCompare`, ties by raw name). At depth 1 this is today's flat order.

### Output (additions only)

Root: `depth`, `hiddenEntries`, `fileCount`, `folderCount` (regular files and directories
only; packages, links and special files are in neither), `listedBytes` (sum of listed regular
files), optional `largestItems` (top five listed files by size, only when at least two files
have a size — the stretch item), and `scope` is `nestedFolders` for depth above 1. `recursive`
stays `false` at every depth: **no number is ever a recursive total**. Entries: `modified`
(ISO 8601, from `st_mtimespec`), `items` (exact direct child count, written only when the
adapter counted every name) and the new kind `package`.

### Bounds and partial listings

`ListingBudget` (in `ContainerSupport.swift`) prices every entry *before* anything is written
against the shared writer's node, line and byte budgets (a conservative upper bound: fixed JSON
syntax plus the exactly escaped path), so a big folder becomes a flagged partial listing
instead of failing with `tooManyNodes`. Other limits: 10,000 entries at most; one directory is
read for at most `maxEntries` visible names; 100,000 names are read in total across listing and
counting passes; cumulative name bytes ≤ `maxMetadataBytes`; the request deadline and
cancellation are checked per directory and every 256 names.

`partial` is set when any limit stops the listing, a folder cannot be opened or read, a mount
point is skipped, a count would be inexact, or the entry budget ends the listing. Unreadable
folders also count toward `inaccessibleEntries`. A count that cannot be exact is **omitted**,
never approximated. A deadline does not preempt a blocking native call; the bounds above keep
each call small.

## ZIP

- `ZIPEntry.modified` flows into `ContainerEntry.modified`. MS-DOS date/time are stored
  wall-clock values with no zone, so the summary also writes `timeZone: "UTC"` whenever any date
  is present; views then display the stored digits unchanged (the extended-timestamp field, a
  real UTC instant, is shown the same way).
- **Encrypted members are listed** (`ZIPArchiveReader.read(…, encryptedEntries: .list)`) with
  `encrypted: true` instead of failing the whole archive. ZIP encrypts payloads, not names, so a
  listing exposes nothing the archive does not already publish; no payload byte is read and
  `readMember` still throws `encryptedContent`. Archives whose *directory* is unreadable (strong
  encryption of the central directory) still fail as malformed. This changes one existing
  expectation (`ZIPRejectsEncryption…`, now `ZIPListsEncryptedMembers…`).
- Oversized directories list their first entries and are flagged `partial` rather than failing;
  a path longer than the line budget is skipped and flags `partial`.

## The listing contract

Any adapter whose summary schema is registered (`SummaryLabelSet`, so its labels are
localized) and whose root JSON has an `entries` array of objects with a string `path` and
`type` (optional `bytes`, `modified`, `encrypted`, `items`) gets **Files** and **Tree**
automatically; there is no format list. The root may carry `partial` and `timeZone: "UTC"`. A
user's own JSON file never qualifies, because only registered summary formats are inspected.
The shape is read from the **concealed** presentation text with `JSONSerialization`; if
concealment broke the JSON, a field has the wrong shape, the text exceeds 8 MiB or there are more
than 20,000 entries, the modes are simply absent (Source and Summary remain).

- **Files** (initial mode when available; amended 2026-10-06 by [decision 027](027-best-in-class-quality-program.md), Q-13,
  owner decision D17a: the package, certificate, disk-image and torrent summaries of
  [decision 017](017-package-and-certificate-inspection.md) open on Summary and keep Files one click away):
  Name, Kind, Size, Modified (Modified (UTC) when the
  listing says so). Hierarchical order with folders first and natural names when the tree
  exists, otherwise the adapter's order. A directory shows no size.
- **Tree**: flat paths nested into folders (`dir/` entries merge with implied parents; a
  repeated file path stays a separate node; a file and folder of one name coexist; dot
  components are ordinary names; empty-component paths are kept in Files only). Bounds: 60,000
  nodes, 64 components; beyond them Tree is absent and Files remains. Items and sizes are
  *listed* facts: exact only when the adapter supplied `items` or an archive listing is not
  partial; otherwise the count or size is shown as **At least …**, and a folder whose contents
  were not listed has no size. Folders open expanded up to 300 nodes, collapsed above.

## Tables

`NativeTablePreviewView` (CSV/TSV and Files) adds, without changing its `display` signature or
the data it shows:

- Click-to-sort headers and a Sort pull-down (columns, ascending/descending) for keyboard use;
  stable (ties keep source order), blanks always last. Typed number/date columns sort by value:
  CSV columns qualify only when *every* non-blank cell parses strictly (ASCII decimals, ISO 8601;
  a zoneless time is read as UTC), so one other cell or a concealed `••••` keeps the column
  textual and cell text is never reinterpreted. Text columns use natural order
  (allocation-free ASCII path, `localizedStandardCompare` otherwise; never mixed within a sort).
- A filter field (Command-F from the table) hiding rows without the typed text, ignoring case,
  accents and width. It searches only displayed (concealed) cells; the needle is capped at 256
  characters; non-ASCII cells are folded once per table (cache capped at 150,000 cells).
- Alternating rows, the system header (stays visible while scrolling), a "n of m rows" status,
  selection that follows the same rows through sort and filter, copy in displayed order, VoiceOver
  labels on the table, filter and Sort menu, and a spoken announcement of each sort.
- A partial listing shows its own localized notice.

## Privacy and security

Concealment is unchanged: summary strings flow through `SummaryWriter`, a path containing a
secret assignment is concealed by the shared filter, and Files, Tree, sorting, filtering and
copy only ever see the concealed text. The filter and sort cannot reveal or confirm concealed
content because they never see anything else. Adapters stay read-only, offline and bounded; the
scan never writes, extracts, follows links or reads child content. File names, paths, dates in
the ISO field and the `UTC` identifier are never translated; app-owned labels, numbers, byte
counts and displayed dates follow the presentation locale.

## Shared-core touches (all additive)

`SummaryWriter` compiles its secret-assignment regex once per writer instead of once per string
(identical behavior); `ContainerEntry` gained defaulted `itemCount`; `ListingBudget` is new in
`ContainerSupport.swift`. Existing callers of `listingDocument` and `ContainerEntry` compile
unchanged. `SafeTable` gained defaulted `columnKinds`/`sortKeys` and a `partialListing`
truncation. Two existing tests changed intentionally: the encrypted-ZIP expectation, and the
interaction test that displayed a listing-shaped folder summary to exercise the Summary outline
(listings now open in Files, so that test uses a non-listing summary).
`tools/test_localization.py` lists formatted-resource keys and gained this family's three.

## Not promised

No recursive size, no complete folder total, no live reload; Finder routing, folder thumbnails,
VoiceOver announcement behavior, native-speaker review of the 26 new strings and behavior in a
signed host are unverified. Kinds are generic (File, Folder, Link, Package), not per-UTType
descriptions. `.DS_Store`, `UF_HIDDEN` and `.hidden` files are not treated specially. The depth
and hidden-items controls appear in the companion only once the settings workstream persists
them.
