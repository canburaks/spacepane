# 007 — Bounded binary inputs and safe secondary presentations

Accepted 2026-10-04 for the implemented expansion. Full installed-host and release
acceptance remains in [PLAN.md](../../PLAN.md).

## Input capabilities

Text decoding is one adapter capability, not a requirement imposed on SQLite,
archives, folders or MIDI. `AdapterRegistration` selects text, binary bytes,
request-owned random access or a directory URL. The central pipeline still classifies,
checks saved file-type policy **before opening or constructing an adapter**, applies
one request deadline/budget and filters the result before rendering. Registrations
are explicit; there is no plugin discovery or downloaded code.

`PreviewByteSource` owns a read-only, no-follow descriptor. Reads charge a cumulative
byte budget even when ranges overlap; offset checks precede allocation. File size,
mtime and ctime are checked before/after reads. This permits bounded ZIP directory,
TAR header and XIP metadata/chunk reads from files larger than the read allowance.
The logical scanned span and decoded output have separate caps. Limits are not
operating-system quotas or a promise to preempt blocking native calls.

Directory enumeration is the narrow exception to the shared descriptor reader:
`FolderSummaryAdapter` opens the authorized directory, uses descriptor-relative
metadata, does not follow links or recurse, and reports partial/inaccessible entries.
It has no arbitrary child-content-reading capability.

## SQLite snapshot boundary

SQLite adapters receive copied bytes, never the source URL. The reader rejects
existing `-wal`, `-shm` and `-journal` siblings, takes conservative SQLite-range read
locks and rechecks source metadata/sidecars before closing. The parser rejects WAL
header mode and deserializes into a private in-memory, read-only SQLite connection.
It does not apply `immutable=1` to a live source database. Busy, inaccessible,
inconsistent and unsupported states decline. No view/trigger/virtual table is
executed; a query authorizer, trusted-schema restrictions and statement limits
constrain generated reads. The small owned C shim exists only because Swift cannot
call SQLite's public variadic configuration function directly.

These controls establish a conservative rollback-mode snapshot path; they do not
claim coherent live-WAL support. Cross-process locks, sidecar permissions and actual
Finder sibling grants have separate validation gates. See SQLite's
[locking protocol](https://sqlite.org/lockingv3.html) and
[read-only deserialization](https://sqlite.org/c3ref/deserialize.html).

## Safe display models

Adapters may synthesize bounded JSON metadata, with sensitive ranges generated at
the same time. Renderers parse only the **concealed** presentation to produce native
outlines, record lists or inert Markdown. The source representation is not an
alternate raw-data channel. Numeric JSON lexemes and user keys remain exact;
app-owned summary field paths are translated separately. SQLite column names,
filenames, paths, schema identifiers and actual source values are never translated.

Malformed JSONL records are wholly concealed while valid records remain readable.
Original record-count provenance disables record indexing if concealment collapses
lines. Logical line numbers continue to describe displayed safe text.

MIDI carries only validated bounded channel events and timing, never raw text/SysEx
metadata or a document-supplied sound-bank URL. Playback is explicit and owned by
the visible renderer. Replacement, disabling, tab hiding, host disappearance and
teardown stop audio; actual Finder audio/sandbox behavior remains a host gate.
Thumbnails remain content-free and never instantiate these parsers or audio views.

## Adding another format

Reuse an existing input/presentation capability where possible. Add its adapter,
logical catalog identity, registration and fixtures. Shared-core changes in this
expansion were necessary for binary/range/directory access and safe MIDI/record
provenance; they are not permission to add per-format host switches later.
