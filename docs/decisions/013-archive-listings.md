# 013 — Archive listings: RAR, 7z, bzip2, xz and Java archives

Date: 2026-10-05. Status: implemented locally with package, corpus and typecheck evidence; Finder
routing, thumbnails, VoiceOver, native-speaker review and signed-host behavior are unverified.
Part of the [competitor parity program](025-competitor-parity-program.md); evidence is recorded in
[the archives validation report](../validation/archives-2026-10-05.md). It builds on
[decision 007](007-binary-inputs-and-safe-presentations.md) (bounded binary inputs and safe
presentations) and [decision 009](009-first-expansion-formats.md) (the existing TAR/GZIP/ZIP/XIP
adapters this extends).

## Scope

Four new independent file-type choices, one new type claim for an existing choice and one new field
on existing listings. Nothing here extracts, decompresses or decrypts a member of any archive.

| Format ID | Types | Suffixes | Input path | Result |
|---|---|---|---|---|
| `archive.rar` | imported `org.webmeister.spacepane.type.rar` (conforms to `public.archive`) | `rar` | random access | RAR 5.0 and RAR 1.5-4.x entry listing |
| `archive.7z` | system `org.7-zip.7-zip-archive` | `7z` | random access | 7z entry listing |
| `archive.bzip2` | system `public.bzip2-archive`, `public.tar-bzip2-archive` | `bz2`, `tbz`, `tbz2` | whole file in memory | TAR listing, text, or a binary notice |
| `archive.xz` | system `org.tukaani.xz-archive`, `org.tukaani.tar-xz-archive` | `xz`, `txz` | whole file in memory | TAR listing, text, or a binary notice |
| `archive.zip` (existing) | adds system `com.sun.java-archive`, `com.sun.web-application-archive` | adds `jar`, `war` | unchanged | unchanged ZIP listing |
| `archive.tar`, `archive.gzip` (existing) | unchanged | unchanged | unchanged | entries gain a `modified` date |

All four new formats keep the `generic` thumbnail policy: a content-free glyph. Thumbnail drawing
belongs to the thumbnails workstream. All are enabled by default and switchable per format through the
standard catalog-driven controls; a disabled type returns `disabledByUser` before any adapter factory
runs and never falls back to a generic reader.

**Types.** On the development Mac (macOS 27 SDK) `.rar` resolves to a dynamic type, so the catalog
imports an app-selected identifier like the earlier `.srt`/`.nfo` cases. Other apps may declare `.rar`
under their own identifier, and Finder then routes by that identifier; only an observed host result can
establish routing. `.7z`, `.bz2`, `.tbz`, `.tbz2`, `.xz` and `.txz` resolve to system declarations. `.jar`
and `.war` resolve to `com.sun.java-archive` and `com.sun.web-application-archive`, both conforming to
`public.zip-archive`, so they join the ZIP choice. `.ear` resolves to a dynamic type and no system
`com.sun.enterprise-archive` exists; claiming it would need a new imported declaration for a
suffix that other Java tools own, so it stays unregistered. `.lzma`/`.tlz`, `.cbr`/`.cb7`, `.zst`,
`.lz4`, `.lzh`, `.cab` and `.arj` are not claimed.

## Module layout

All new adapter code lives in `PreviewFormats/Containers/`; contracts and orchestration did not change.

| File | Responsibility |
|---|---|
| `ArchiveFormatAdapters.swift` | registrations; shared listing rules (entry cap derived from the node budget, timestamp conversion, executable-stub detection); CRC-32; a bounds-checked byte reader |
| `RARListingAdapter.swift`, `RAR5Listing.swift`, `RAR4Listing.swift`, `RARUnicodeName.swift` | RAR signature detection and the two header walkers; RAR 2.x-4.x compact Unicode names |
| `SevenZipListingAdapter.swift`, `SevenZipStreamsInfo.swift`, `SevenZipFilesInfo.swift` | signature and start header, `EncodedHeader` handling, the header grammar, the file table |
| `LZMADecoder.swift`, `LZMA2Decoder.swift` | bounded LZMA and LZMA2 decoders for header streams and large-dictionary xz |
| `BZip2Decompression.swift` and the `BZip2Shim` C target | streaming bzip2 through the system libbz2 |
| `CompressedStreamAdapters.swift`, `CompressedStreamXZ.swift` | the shared decoded-payload rule, the bzip2 and xz adapters, the bounded xz block decoder |
| `BoundedDecompression.swift`, `TARListingAdapter.swift` (existing, owned here) | bzip2 entry point and xz routing; TAR `modified`, GZIP routed through the shared payload rule |
| `PreviewContracts/ArchiveFormatIDs.swift`, `PreviewRenderers/SafeSchemaLabels+Archives.swift` | format IDs; the summary label set |

**Shared decoded-payload rule.** GZIP, bzip2 and xz decode their stream under a cap and then treat the
bytes the same way: a TAR header at offset zero (all-zero block or `ustar` magic) is listed by the TAR
reader, valid UTF-8/UTF-16 text without NUL is returned as text for the shared concealment stage, and
anything else becomes a `payloadKind: binary` notice with the decoded size. `CompressedStreamPayload`
holds that logic once. GZIP output is byte-for-byte what it was.

## RAR

Written from the public RAR 5.0 archive format technote and the RAR 4 format description.

- **Detection.** `Rar!\x1A\x07\x01\x00` is RAR 5, `Rar!\x1A\x07\x00` is RAR 4. RAR 1.4 (`RE~^`) and files
  that start like an executable (`MZ`, ELF, Mach-O: self-extracting stubs) are `unsupportedFormat`;
  anything else is `malformedDocument`. A file whose first block is not the main header (a volume
  fragment) is `unsupportedFormat`.
- **Walking.** Random access: a 7-byte prefix, then the rest of the header. Data areas are skipped by
  their declared size and never read; the size must fit inside the file. RAR 5 header CRC-32 covers the
  size field and header; RAR 4 CRC-16 is the low half of the CRC-32 of everything after the CRC field
  (verified for the block types that are interpreted). Variable integers are bounded to ten bytes and 64
  bits; header size is capped at the technote's 2 MiB.
- **Entries.** Path through `listableArchivePath` (RAR 4 on MS-DOS/OS/2/Win32 hosts converts backslashes
  first), kind (file, directory, symlink, hardlink via the RAR 5 redirection record or Unix attributes),
  unpacked size (null when stated as unknown), modification time and `encrypted` for file-level
  encryption (RAR 5 encryption record, RAR 4 flag). Names without a Unicode companion decode as UTF-8
  when valid and otherwise as code page 437 (the MS-DOS default); the original codepage is not recorded.
  Symlink and hardlink targets, comments and recovery data are never shown.
- **Dates.** RAR 5 header time (Unix seconds), or the file-time extra record in FILETIME or Unix-seconds
  form. The nanosecond Unix variant is not decoded rather than guessed. RAR 4 MS-DOS time carries no zone
  and is shown as UTC. Values outside 1970-2200 are dropped.
- **Archive flags** become summary fields: `solid`, `multiVolume`, `volumeNumber` (RAR 5, one-based),
  `locked`, `recoveryRecord`.
- **Encryption.** A RAR 5 archive-encryption header or the RAR 4 encrypted-headers flag is
  `encryptedContent`: names cannot be read. Nothing is decrypted or guessed.
- **Partial results.** Hitting the entry cap, exhausting the input budget after the main header, or a
  missing end-of-archive block reports `partial: true`.

## 7z

Written from the public 7z format description (`7zFormat.txt`).

- **Signature header.** Start-header CRC, version (major 0 only), next-header offset, size and CRC. A
  zero-size next header is an empty archive. Offsets and sizes are checked against the file and the
  budget before the header is read.
- **Header grammar.** `Header` and `EncodedHeader` (up to four levels), `ArchiveProperties`,
  `StreamsInfo` (pack info, folders with coders and bind pairs, per-folder unpack sizes and digests,
  substreams), `FilesInfo` (UTF-16LE names, empty-stream/empty-file/anti vectors, modification times,
  attributes). Every count is bounded by the bytes that remain before it sizes anything.
- **Entries.** Directories come from the empty-stream vector or the Windows directory attribute, symlinks
  from the Unix-extension attribute word. Anti items (deletion markers in update archives) name no file
  and are skipped. Sizes come from substreams. A folder that uses the AES coder marks its members
  `encrypted`; names stay listed. `solid` reports whether any folder holds more than one stream.
- **Compressed headers.** Only the header stream is decoded, as a chain of Copy, LZMA or LZMA2 coders
  (simple one-input one-output coders). Any other coder is `unsupportedFormat`, the AES coder is
  `encryptedContent`. The packed size, declared output (at most 8 MiB) and dictionary are checked before
  any allocation, the decoded header's CRC-32 is verified, and member payloads are never decoded.

## LZMA and LZMA2

Original implementations from the public LZMA format description (the LZMA SDK specification is in the
public domain); no code was copied. The decoder keeps the whole bounded output as its window, so
allocation follows the declared output size (already capped), never the declared dictionary. The
dictionary is still limited to 64 MiB as policy and bounds how far a match may reach. The range decoder
fails instead of reading past its input, a match may not run past the declared output or before the
dictionary start, LZMA2 chunk control bytes, property resets and `lc + lp <= 4` are validated, each LZMA2
chunk must consume exactly its stated bytes and end with a finished range coder, and the request
deadline and cancellation are checked every 4,096 decoded symbols and every LZMA2 chunk.

## bzip2 and xz

- **bzip2.** The macOS SDK's system `libbz2` through the small `BZip2Shim` C target (modeled on
  `SQLiteSafetyShim`, built with `-fapplication-extension`). The shim exposes only create, a bounded decode
  step and destroy; no compression entry point is reachable. Output is produced in 32 KiB steps against
  the decoded cap with a checkpoint per step; libbz2's own memory is bounded by the format (one block of
  at most 900 KB, about 3.6 MB). Concatenated streams decode in order; trailing bytes other than a further
  `BZh` stream are malformed. **Newly linked system library: `libbz2` (`/usr/lib/libbz2.dylib` in the
  SDK).** The macOS SDK has no module map for it, hence the shim. The C object embeds an autolink request
  (`#pragma comment(lib, "bz2")` with `-fms-extensions`) in addition to the package's linker setting,
  because the repository's host-tool scripts link package objects without reading linker settings.
- **xz.** Streams whose LZMA2 dictionary is at most 8 MiB go through the system `Compression` decoder
  after the existing structural preflight (unchanged behavior, shared with XIP). Streams that declare 8-64
  MiB (for example `xz -9`, which records 64 MiB even for a few bytes) go through this package's bounded
  LZMA2 decoder: the index states every block's output size, the total is checked before any allocation,
  every header CRC is verified, and CRC-32, CRC-64 and SHA-256 block checks are verified. Above 64 MiB the
  stream is `inputTooLarge`. Only a single LZMA2 filter, one stream and the check types above are
  supported; BCJ or other filter chains, concatenated streams and unknown check types are declined.

Both compressed-stream adapters, like GZIP, read the whole file under the request's input budget (1 MiB
by default) and decode up to `min(64 MiB, 64 x input budget)`. Larger files fail with `inputTooLarge`.

## TAR modification times

Entries gain `modified` from the header's octal field, or from a PAX `mtime` record (decimal seconds,
possibly fractional) when present. A blank or unparsable field means no time. The random-access and
decoded-buffer readers share the rule. Because each entry can now add two more JSON nodes, the entry cap
for TAR (and every archive in this family) is derived from the node budget:
`min(10,000, (maxJSONNodes - 40) / 11)`, 1,814 entries at the default 20,000 nodes, down from 2,500 for
TAR. A larger archive still lists the first entries with `partial: true`.

## Summary schema, labels and privacy

Every new format writes the shared listing JSON built by `listingDocument` (`archiveFormat`,
`listedEntries`, `partial`, `entries[]` with `path`, `type`, `bytes`, optional `modified` and `encrypted`)
plus the root fields above, so the listings workstream's Files and Tree modes derive from the standard
`entries` array. `SafeSchemaLabels+Archives.swift` registers one label set for the four formats with seven
new localized keys (`preview.archive.*`) and reuses the shared listing keys; paths and ISO 8601 dates
stay verbatim and booleans and counts follow the presentation locale. Format names and descriptions are
`format.archive.<id>.name`/`.description`. All 15 new strings have draft translations in the 14 shipped
languages that await native-speaker review.

Names pass through the shared `SummaryWriter`, which marks any path containing a secret-like assignment as
sensitive so the shared filter conceals it in the source, summary and every derived mode. No payload,
comment, link target or password check value is read or shown. bzip2 and xz text payloads are returned
as plain text, so the shared key/value and credential-pattern concealment applies exactly as it does for
a `.txt` file; binary payloads show only their decoded size. No `PreviewImage` is produced.

## Security and limits

| Concern | Control |
|---|---|
| Hostile sizes and counts | Every count, offset and size is checked against the file, the remaining header bytes and the budget before it sizes an allocation or a read |
| Source reads | Only headers are read through the request-owned random-access source; reads are charged cumulatively; payload ranges are never touched (tests record every range) |
| Decompression bombs | Output capped before and during decoding; the declared sizes of 7z headers (8 MiB) and xz blocks are checked before allocation; bzip2 steps are bounded |
| Cancellation and deadlines | Checkpoint before any input access and in every loop; the shared adapter tests cover all four registrations |
| Path traversal | Since merging the Safety Lens ([decision 012](012-safety-findings.md)), RAR and 7z list absolute paths, `..` components and drive prefixes as inert text and the shared archive risk analyzer flags them, like ZIP and TAR; empty names and control characters still fail. Nothing is extracted. Formats that read members by name keep the strict `safeArchivePath`. |
| Malformed input | Header CRCs verified; truncation, bad variable integers, impossible sizes and unknown layouts fail with typed `PreviewFailure` values and are never presented as complete |
| Encryption | Reported as `encryptedContent` for headers; per-entry `encrypted` flag for member data; no key derivation or password prompt exists |
| Dependencies | None third-party; system libraries `libbz2` (new), `Compression` and `zlib` (existing); `bsdtar` (libarchive) and py7zr were used outside the repository only to cross-check hand-built fixtures and to generate test vectors |

## Not promised

- Extracting, previewing or decompressing archive members; archive comments; recovery-record repair.
- RAR or 7z member passwords; encrypted headers (reported, not listed).
- Self-extracting archives, multi-volume reassembly, `.7z.001` splits and split ZIP.
- CBR/CB7 comics, `.zst`, `.lz4`, `.lzh`/`.lha`, `.cab`, `.arj`, `.lzma`/`.tlz`, `.ear`, BCJ/Delta or other
  filter chains in 7z headers or xz streams, multi-stream xz.
- RAR 1.4 archives and the RAR 5 nanosecond Unix time variant.
- Verified Finder routing for any of these types, thumbnails, VoiceOver behavior, translated layout or
  signed-host behavior. A companion preview or `qlmanage` result would not prove them.

## Known limitations

- Compressed streams (GZIP, bzip2, xz) larger than the input budget (1 MiB by default) are declined with
  `inputTooLarge`; typical source tarballs exceed that. A prefix-decoding partial listing, or a larger
  default budget for these registrations (the registration contract supports a default budget only for
  geometry), is the natural follow-up and needs a shared-contract decision.
- Dates are ISO 8601 strings in the summary, not locale-formatted: the label mechanism has no date field
  type. The Files table may format them.
- RAR 4 non-Unicode names that are not UTF-8 are decoded as code page 437, which is only the common
  default; MS-DOS times are shown as UTC.

## Shared files touched, and why

Only the family's own marker lines: `TextAdapter.swift` (`+ ArchiveFormatAdapters.registrations`),
`SafeSchemaLabels.swift` (`.archives`), `PreviewStrings.swift` (seven keys), `generate_host_fixtures.py` and
`generate_appearance_samples.py` (one call each), plus catalog entries, generated manifests, localization
inputs and outputs and the sample manifest through their tools. `Package.swift` gains the `BZip2Shim`
target and the `PreviewFormats` dependency on it. `TARListingAdapter.swift` and `BoundedDecompression.swift`
are archive-owned files changed as described. Nothing else in the shared contracts changed.
