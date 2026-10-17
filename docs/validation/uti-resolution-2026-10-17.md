# Why `.sqlite`, `.db` and `.rar` resolve to dynamic types — 2026-10-17

The lead session found on 2026-10-17 that Quick Look shows the generic icon for `07-stations.sqlite`, the file the App Review notes tell the reviewer to press Space on, and that `UTType(filenameExtension:)` returns a dynamic type (`dyn.*`) for `sqlite`, `sqlite3`, `db`, `db3`, `s3db` and `rar` while `ipynb`, `gguf`, `vsix`, `whl` and `3mf` resolve to the declared types. This record establishes the cause, says what a reviewer on a clean Mac sees, and names the fix. Everything below was done read-only on the system: no `lsregister -kill`, no unregistration, no garbage collection, no change to System Settings.

## Verdict

**The cause is a product defect in the imported type declarations, not this Mac's Launch Services state.** The three imported types `org.sqlite.sqlite`, `org.apache.parquet` and `org.webmeister.spacepane.type.rar` list only `public.database` or `public.archive` in `UTTypeConformsTo`. macOS declares both of those as abstract base types with no parent of their own, so the three types conform to neither `public.data` nor `public.item`. Launch Services resolves the type of a regular file only among types that conform to `public.data`; it skips the three declarations and makes a dynamic type from the extension, and Quick Look has no provider for a dynamic type. A clean Mac behaves the same, because the parent declarations come from macOS and the imported declarations come from the build. **Build 5, now in App Review, previews no `.sqlite`, `.sqlite3`, `.db`, `.parquet` or `.rar` file through Finder on any Mac.** The fix is to add `public.data` to the conformance of the three catalog entries and ship a new build; no change on this Mac or on the reviewer's can substitute for it.

## Setup

- macOS 27.2 (26B5101f), Xcode 27.1, Apple silicon. `/Applications/SpacePane.app` is 1.1.0 build 5, TestFlight-signed, the build in App Review. Its three `Info.plist` files carry 61 imported type declarations each, identical to the repository's `Configuration/App-Info.plist`, `Preview-Info.plist` and `Thumbnail-Info.plist` (compared after sorting by identifier).
- Inputs: the Launch Services dump the lead took at 12:42 (`lsregister -dump`, 299,095 lines), the installed plists, the repository's `FormatCatalog.json` and `script/sync_manifests.py`, the SDK header `UTCoreTypes.h`, `/System/Library/CoreServices/CoreTypes.bundle/Contents/Info.plist`, and the pre-split history in `~/Github/prev`.
- Programs: two small Swift command-line programs built with `swiftc` in the session's scratch folder. One asks `UTType(identifier)`, its `supertypes`, `UTType(filenameExtension:)` and `UTType.types(tag:tagClass:conformingTo:nil)` for every imported identifier and tag. The other asks `UTType(tag:tagClass:conformingTo:)` with the filters `nil`, `.data` and `.item`, and reads `URLResourceValues.contentType` of empty files named `sample.<ext>`. Quick Look routing was observed with `qlmanage -p` on a one-table SQLite file and a one-entry zip named `.whl`, attributing the provider by whether a `PrevPreviewExtension` process appeared within five seconds.

## Hypothesis 1: declarations under `public.database` and `public.archive` — confirmed, with the mechanism

Every one of the 61 imported identifiers resolves (`UTType(identifier).isDeclared == true`, not dynamic). What differs is whether a file with the tag resolves to it. Grouped by the declared parent:

| Declared parent | Identifiers | Tags | Tags that resolve to `dyn.*` |
|---|---|---|---|
| `public.database` | 2 | 4 | 4: `.sqlite`, `.sqlite3`, `.db` (`org.sqlite.sqlite`), `.parquet` (`org.apache.parquet`) |
| `public.archive` | 1 | 1 | 1: `.rar` (`org.webmeister.spacepane.type.rar`) |
| `public.plain-text` | 13 | 33 | 10, all extra Markdown tags (see the side finding below) |
| `public.data` | 15 | 21 | 0 |
| `public.zip-archive` | 7 | 8 | 0 |
| `public.json` | 5 | 5 | 0 |
| `public.xml` | 7 | 9 | 0 |
| `public.text` | 9 | 18 | 0 |
| `public.source-code` | 1 | 135 | 0 |
| `com.apple.xml-property-list` | 1 | 1 | 0 |

The mechanism, each step observed:

1. **macOS declares the two parents without a parent.** In `CoreTypes.bundle` the exported declarations of `public.database` and `public.archive` have no `UTTypeConformsTo` key at all; `public.zip-archive` conforms to `com.pkware.zip-archive`, `public.json` to `public.text`. At runtime `UTType("public.database").supertypes` and `UTType("public.archive").supertypes` are both empty and `conforms(to: .data)` is false for both. The macOS 27 SDK header documents them the same way: `public.archive` and `public.database` ("A database store.") carry no "conforms to" line, unlike the physical types around them. The declarations are macOS's, not SpacePane's, and nothing in them refers to the OS version; whether macOS 15.2 declares them identically is the one open input, and the virtual-machine test below reads it directly.
2. **The three SpacePane types inherit that.** `UTType("org.sqlite.sqlite").supertypes == [public.database]`, `UTType("org.apache.parquet").supertypes == [public.database]`, `UTType("org.webmeister.spacepane.type.rar").supertypes == [public.archive]`. None conforms to `public.data` or `public.item`. Every other imported type conforms to `public.data` through its parent.
3. **Launch Services knows the declarations and rejects them for files.** With no filter, `UTType(tag: "sqlite", tagClass: .filenameExtension, conformingTo: nil)` returns `org.sqlite.sqlite`, and `UTType.types(tag:…)` lists exactly that type; the same holds for `db`, `rar` and `parquet`. With the filter `.data`, which is what `UTType(filenameExtension:)` applies by default, the answer is `dyn.ah62d4rv4ge81g6pqrf4gn` for `sqlite`, `dyn.ah62d4rv4ge80k2u` for `db`, `dyn.ah62d4rv4ge81e2pw` for `rar` and `dyn.ah62d4rv4ge81a2pwsf40n7a` for `parquet`. With the filter `.item` the answer is a different dynamic type. `whl`, whose type conforms to `public.data` through `public.zip-archive`, returns `org.webmeister.spacepane.type.python-wheel` under every filter.
4. **Files get the dynamic type.** `URLResourceValues.contentType` of `sample.sqlite`, `sample.db`, `sample.rar` and `sample.parquet` is the respective `dyn.*` type; `sample.whl` gets its declared type. Finder, Spotlight and Quick Look read this value.
5. **Quick Look then has no provider.** `qlmanage -p real.sqlite` never started `PrevPreviewExtension`; `qlmanage -p real.whl` did. The preview extension does claim `public.data` exactly (for files without an extension, decision 011), and the dynamic type does conform to `public.data`, yet Quick Look does not route the dynamic type to it; the lead saw the same generic icon in Finder. The `qlmanage -c <type>` runs that tried to force a content type were inconclusive: the flag changed nothing for either file in either direction, so it evidently does not reach app-extension providers and is not a usable control.

Why older records say SQLite worked: the Finder matrix of 2026-10-04 recorded `database.sqlite` as resolved to `org.sqlite.sqlite` with a summary shown in Finder, and the App Store screenshot of a SQLite preview was captured on 2026-10-11. The declaration already conformed only to `public.database` on 2026-10-04 (`Configuration/Preview-Info.plist` at `e77456d` in `~/Github/prev`), so the declaration itself has never been able to resolve a file. The likely explanation is that TablePro's declaration of the same identifier was the active one on those days: its declaration conforms to `public.database` **and** `public.data`, and whenever it is active `.sqlite` resolves to `org.sqlite.sqlite` and Quick Look asks SpacePane. Today the active declaration is the one from `/Applications/SpacePane.app`, so the defect shows. This fits the screenshot date exactly (Spotlight's `kMDItemDateAdded` for `/Applications/TablePro.app` is 2026-10-11 10:27 UTC, the day the SQLite screenshot was taken) but not necessarily 2026-10-04: the bundle's own modification date is 2026-09-17, so TablePro may have been present then or may have been added or updated on 2026-10-11; the dump shows only today's state. The test that settles it is in "What would settle the rest".

## Hypothesis 2: conflicting declarations from other bundles — not the cause

The dump was parsed for every declaration of each of the 61 identifiers, with the declaring bundle and the active flag:

| Identifier | Active declaration today | Other bundles that also declare it |
|---|---|---|
| `org.sqlite.sqlite` | SpacePane (`/Applications/SpacePane.app`): conforms `public.database`, tags `.sqlite .sqlite3 .db` | TablePro (inactive): conforms `public.database, public.data`, tags `.db .db3 .s3db .sl3 .sqlite .sqlite3 .sqlitedb` |
| `org.apache.parquet` | SpacePane: conforms `public.database`, tag `.parquet` | TablePro (inactive) |
| `org.webmeister.spacepane.type.rar` | SpacePane: conforms `public.archive`, tag `.rar` | none |
| `org.ietf.mhtml` | SpacePane: conforms `public.data` | Brave, ChatGPT, Google Chrome (inactive) |
| `com.topografix.gpx` | Xcode | Xcode only |
| `net.daringfireball.markdown` | CoreTypes (macOS): tags `.md .markdown`, `text/markdown` | Agenda, Claude, CodeRunner, CotEditor, MacWhisper, Xcode |
| `org.bittorrent.torrent` | Folx | Folx only |
| `org.chromium.extension` | Google Chrome | Brave, Google Chrome |
| `org.idpf.epub-container` | CoreTypes (macOS) | Books |
| `org.w3.webvtt` | CoreTypes (macOS) | MacWhisper |
| the other 50 | SpacePane, sole declarer | none |

Three conclusions follow. First, the active declaration of `org.sqlite.sqlite` is SpacePane's own, so Launch Services is not declining to pick a type; it picked SpacePane's and that one cannot match a file. Second, the TablePro-only tags `db3` and `s3db` resolve to a dynamic type under **every** filter, including `nil`, which proves TablePro's declaration is not consulted at all; the lead's observation that they fail was a symptom of the same choice, not of a conflict. Third, `.rar` has no competing declaration anywhere and fails identically, which rules out conflict as a necessary condition. Removing TablePro would not help; on the contrary, TablePro's declaration becoming active is the only state in which `.sqlite` previews work with build 5, and that is a state the reviewer's Mac will not be in.

Side finding, outside this task's question: macOS itself owns `net.daringfireball.markdown` (exported from `CoreTypes.bundle` with the tags `.md` and `.markdown`), and `com.topografix.gpx`, `org.bittorrent.torrent`, `org.chromium.extension`, `org.idpf.epub-container` and `org.w3.webvtt` are owned by other declarers here. SpacePane's import of `net.daringfireball.markdown` adds ten tags (`mdown`, `mkd`, `mdx`, `rmd`, `qmd`, `mkdn`, `mdwn`, `mdtxt`, `mdtext`, `markdn`); because the system's exported declaration wins everywhere, those ten extensions resolve to dynamic types on every Mac and never reach SpacePane through Finder. The other five identifiers resolve on this Mac through the other declarer and on a clean Mac through SpacePane's own import, so they are fine. The Markdown tags need their own decision; this record only notes them.

## Hypothesis 3: stale registrations — present, not the cause

Bundle registrations named SpacePane in the dump, with whether the path still exists (paths trimmed of the trailing registration id before testing):

| Registration | Path | Exists |
|---|---|---|
| `0x1564` | `/Applications/SpacePane.app` | yes; its declarations are the active ones |
| `0xfc8` | `~/Github/spacepane/spacepane/.build/xcode/Build/Products/Debug/SpacePane.app` | yes |
| `0x994` | `~/Github/spacepane/spacepane/dist/PrevPrototype.app` (identifier `invalid.example.previewprototype.companion`) | yes |
| `0x8a0` | `~/Github/spacepane/.build/xcode/Build/Products/Release/SpacePane.app` (pre-split path) | no |
| `0xb08` | `/private/tmp/claude-501/…/ArchiveIntermediates/Prev/InstallationBuildProductsLocation/Applications/SpacePane.app` | no |

Two registrations point at deleted paths. They hold inactive copies of the same declarations and change nothing about resolution; `lsregister -gc` would remove them and is harmless, but it is cosmetic. Nothing was garbage-collected.

## What the owner can do on this Mac

Nothing in Launch Services fixes this, because the active declaration is the shipped one and its content is the defect. In order of usefulness:

1. **Build with the corrected catalog (below), install that build in `/Applications`, open it once, then test.** This is the only action that also fixes the reviewer's experience.
2. To see the fixed behaviour before rebuilding, the owner could make TablePro's declaration active by removing SpacePane's registrations (`lsregister -u` on the three existing paths and `-gc` for the two stale ones); `.sqlite` would then route to SpacePane through TablePro's conformance. This proves nothing about a clean Mac and was not done.
3. `lsregister -gc` alone: tidies the two stale rows, no effect on resolution.
4. `lsregister -kill`, moving TablePro, or System Settings changes: no effect on the cause; not recommended.

## What a reviewer on a clean Mac sees

The same thing. Both inputs to the resolution are identical on any Mac: the parent declarations come from macOS (abstract since the type tree was defined, and documented so in the macOS 27 SDK), and the imported declarations come from build 5's plists. A clean Mac has no TablePro to mask it. So for the review build, pressing Space on `07-stations.sqlite` shows the generic icon with the file name and size, not SpacePane's summary. The notes' step that names that file therefore fails as written; the other samples (`.ipynb`, `.whl`, `.3mf`, source files) route normally. `.parquet` and `.rar` samples, if the reviewer tries them, fail the same way.

The one dependency on the OS version is whether macOS 15.2's `CoreTypes.bundle` also declares `public.database` and `public.archive` without a parent. Apple's type reference describes both as base types, and no SpacePane record claims a working `.sqlite` preview on macOS 15, so the expectation is that macOS 15 behaves the same; the virtual machine can confirm it. (Apple's documentation pages could not be fetched from this session to quote.)

## Test on the macOS 15.2 virtual machine

Not run here. Expected result: the dynamic type for `.sqlite`, the declared type for `.whl`.

1. Copy the build 5 app from the Release archive (or from `/Applications` here) to `/Applications` on the VM and open it once so that Launch Services registers it. Enable the preview extension in System Settings.
2. Create a one-table database and a control file:
   ```
   sqlite3 ~/Desktop/stations.sqlite "create table t(a); insert into t values(1);"
   cp /Applications/SpacePane.app/Contents/Info.plist ~/Desktop/control.plist
   ```
3. Ask macOS for the types, no compiler needed:
   ```
   mdls -name kMDItemContentType -name kMDItemContentTypeTree ~/Desktop/stations.sqlite
   mdls -name kMDItemContentType ~/Desktop/control.plist
   /System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -dump | grep -A 8 "^uti: *public.database$"
   ```
   The defect reproduces when the first command prints a `dyn.ah62…` identifier and the `public.database` block shows no `conforms to:` line. If instead it prints `org.sqlite.sqlite`, the macOS 15 type tree differs and build 5 works there; record that in `host-matrix.json`.
4. Select `stations.sqlite` in Finder and press Space. Generic icon means no provider; the SpacePane summary means the type resolved.
5. If Xcode is on the VM, the two scratch programs from this session can be rebuilt there for the full table; their source is in the session's scratch folder, not in the repository.

## The fix

Catalog: in `Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json`, the `importedContentTypes[].conformsTo` of `database.sqlite` (`org.sqlite.sqlite`), `data.parquet` (`org.apache.parquet`) and `archive.rar` (`org.webmeister.spacepane.type.rar`) must make the type conform to `public.data` as well as to its semantic parent, the way TablePro declares `org.sqlite.sqlite` and the way `public.zip-archive` is declared by macOS. The field is a single string today; `script/sync_manifests.py` writes it as a one-element `UTTypeConformsTo` array, and `FormatCatalog.swift` decodes it as `String` and uses it for `UTType(importedAs:conformingTo:)` when a command-line process runs before registration. Either make the field an array (`["public.database", "public.data"]`) and update those two consumers, or keep the string and have the sync script append `public.data` whenever the parent does not conform to it. The array is the honest shape; the catalog test should then assert, for every imported declaration, that at least one listed parent conforms to `public.data`, so the defect cannot return with the next format.

Generated plists: after the catalog change, `python3 script/sync_manifests.py` rewrites `UTImportedTypeDeclarations` in `Configuration/App-Info.plist`, `Configuration/Preview-Info.plist` and `Configuration/Thumbnail-Info.plist`; the three entries gain `public.data` in `UTTypeConformsTo`. No other plist field is involved: `QLSupportedContentTypes` already lists the three identifiers, and `UTTypeTagSpecification` is correct.

Build: **a new build is required.** The declarations live in the bundle, Launch Services reads them from the installed app, and the reviewer runs the submitted build. Build 5 cannot be repaired on the reviewer's side. The website's data sync reads `FormatCatalog.json`, so `npm run data:sync` in `spacepane-web` follows the catalog change.

Until a corrected build is submitted, the review notes should not direct the reviewer to a `.sqlite` sample; that is a documentation decision for the owner, recorded here as the consequence.

## What would settle the rest

- Why SQLite previewed on 2026-10-04 and 2026-10-11: run `lsregister -dump` on a Mac where it previews and read which bundle's `org.sqlite.sqlite` block is active. If it is TablePro's, the explanation above is confirmed. There is no way to read this Mac's state on those dates.
- Why Quick Look does not fall back to the extension's exact `public.data` claim for a dynamic type: a Quick Look question, not needed for the fix. The observation (no extension process for `real.sqlite`, extension process for `real.whl`) is what matters.
- macOS 15.2: step 3 of the VM test.

## Observed after installing build 6

2026-10-17, 18:15 to 18:21, macOS 27.2 (26B5101f), Apple silicon. The TestFlight-signed build 5 was removed from `/Applications` by the owner (root-owned; a copy is kept under `.build/installed-backup/`), the development-signed 1.1.0 (6) archive from `build6-integration-2026-10-17` was copied there with `ditto` and opened once.

- `pluginkit -mAD`: the preview extension stays enabled under the same identifier; the thumbnail extension stays registered and not enabled.
- `UTType(filenameExtension:)`: `sqlite` → `org.sqlite.sqlite` (declared), `rar` → `org.webmeister.spacepane.type.rar` (declared), `ipynb` unchanged. `db3` and `s3db` (TablePro-only tags) still resolve to dynamic types, as expected: that declaration is inactive. `mdls -name kMDItemContentType` on `stations.sqlite` now prints `org.sqlite.sqlite`.
- Finder: selecting `stations.sqlite` and pressing Space opens SpacePane's preview (Rows: 3 · Columns: 5 · Size: 119 kB, modes Source, Summary, Table; no Filter field). Recorded in `docs/validation/host-matrix.json` as host `mac-build6-2026-10-17`, `database.sqlite` finderPreview = provider.
- The installed app carries `en.lproj` only (6 folders across the app, the two extensions and their nested bundles), the pruning phase's result.

Not observed: thumbnails, macOS 15, a store- or TestFlight-signed build 6.
