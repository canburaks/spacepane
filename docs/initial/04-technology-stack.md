# Task 4 — Technology stack, customization, and performance

Date: 2026-10-03. Status: research complete; architecture recommendations are not runtime measurements. Working product name: **Prev**. Deployment baseline: **macOS 15**; build with a supported Xcode toolchain selected and recorded during implementation.

- [x] Compare native and cross-platform stack options.
- [x] Define customization, parser, concurrency and packaging boundaries.
- [x] Identify candidate dependencies and measurable prototype gates.

## Decision

Use a **native Swift hybrid**: SwiftUI for the companion application's scenes and settings; an AppKit Quick Look view controller with small hosted SwiftUI components; AppKit text, outline, and table adapters where selection, virtualization, or typography requires them. Put format detection, budgets, parsers, settings models, and redaction in local Swift packages shared by the application and extensions.

Use an **Xcode application project with embedded preview and thumbnail extension targets**, plus SwiftPM for reusable libraries and their tests. A standalone SwiftPM executable does not by itself establish the signed app/extension packaging and entitlements required here. Apple's Quick Look documentation distinguishes view-controller and data-based extension implementations; the interactive product needs the former as its primary path. [Quick Look UI](https://developer.apple.com/documentation/QuickLookUI), [Swift Package Manager](https://github.com/swiftlang/swift-package-manager).

This is an engineering choice for this product, not a measured claim that SwiftUI, AppKit, or Swift is universally faster. The critical costs are extension cold start, decoding and layout, tree expansion, highlighter grammars, and bounded I/O. Benchmark these before finalizing implementations.

## Alternatives and tradeoffs

| Option | Customization | Expected cost/risk — inference | Decision |
|---|---|---|---|
| SwiftUI shell + AppKit content + shared Swift core | Native controls, full attributed-text/font access, custom renderer adapters | Some bridging and dual-framework expertise; small platform-specific adapters | Recommended |
| SwiftUI everywhere | Strong settings composition and adaptive layout | Rich selectable highlighted text and dense outline/table behavior may need workarounds; test performance rather than assume | Use where it meets acceptance gates |
| AppKit everywhere | Full control of responder chain, windows, text, and tables | More imperative state and view maintenance | Use selectively, not as a prerequisite for all screens |
| WKWebView for every preview | CSS typography, HTML tables, broad JS renderer ecosystem | Web process startup and memory, content sanitization, network suppression, more complex native selection/accessibility integration | Optional rich-document renderer only if a measured need justifies it |
| Electron, Tauri, or Flutter companion | Cross-platform UI tooling | Still requires native Quick Look targets and a second preferences/UI stack; cross-platform reuse has little product value here | Do not adopt |
| Rust/C++ parsing core | Useful existing parsers and low-level control | FFI, toolchain, lifetime, exception, symbol-size and auditing costs | Narrow library wrappers only when evidence warrants them |
| External Homebrew/Python/Node/Ruby tools | Many available file converters | Installation dependency, cold process cost, extension restrictions and executing untrusted file-driven behavior | Exclude from shipping runtime |

## Rendering and customization architecture

### Text and code

Start with read-only `NSTextView` using TextKit 2, a bounded document, and a line-number gutter. Verify no required API silently switches the view into TextKit 1 compatibility mode. Compare against a simpler bounded TextKit implementation if line numbering, long lines, or selection regress. Apple's TextKit model provides a viewport layout controller; this supports the experiment but does not prove a specific app is virtualized correctly. [TextKit](https://developer.apple.com/documentation/appkit/textkit?language=objc), [Meet TextKit 2](https://developer.apple.com/videos/play/wwdc2021/10061/).

Keep text content and token ranges separate from theme attributes. Changing colors should remap token styles rather than parse again; changing font metrics triggers layout. Parse bounded input off the main actor, and apply bounded attribute batches on the UI actor. Avoid one SwiftUI `Text` or view per token, whole-file attributed-string rebuilding on every setting change, and copying source bytes for each row.

Use installed fonts through `NSFontDescriptor`/Core Text, with a system monospaced fallback. Offer font family, size, weight, italic, line spacing, tab width, ligatures, wrapping, and semantic token styles. Expose variable-font axes only when the font reports them. Clamp imported values and gracefully handle a removed font. Font size is intentionally user-configurable content styling; standard UI labels retain native semantic styling. [Core Text](https://developer.apple.com/documentation/coretext), [CTFontCopyVariationAxes](https://developer.apple.com/documentation/coretext/ctfontcopyvariationaxes(_:)).

### Structured data

Use stable node IDs and lazy child materialization for JSON/YAML/TOML/plist outlines. Native `NSOutlineView` is the first dense-tree candidate; SwiftUI `OutlineGroup` is appropriate for small trees if it passes the same tests. Preserve JSON number lexemes, duplicate-key warnings and source order where feasible; do not convert all numeric values through `Double`. An incomplete prefix of a JSON file is **source text**, not a valid structured tree.

Use paged `NSTableView` or a measured SwiftUI `Table` implementation for SQLite and CSV. Display loaded rows/cells and truncation explicitly. Do not issue automatic full-table counts or unrestricted sorting over huge datasets.

### Markdown and rich documents

Start with `swift-markdown` and a native, block-based renderer supporting a documented GFM subset: headings, paragraphs, lists, links, quotes, code, tables, and task lists. The package parses Markdown; it does not supply a complete application UI. Validate block virtualization, continuous text selection, copy semantics, accessibility, and table overflow as a dedicated renderer gate. [Swift Markdown](https://github.com/swiftlang/swift-markdown).

If native rendering cannot meet those needs within a reasonable implementation scope, benchmark a narrowly scoped WKWebView renderer before switching. Its required policy is app-generated sanitized HTML, nonpersistent website data, blocked remote resources, blocked navigation by default, no document-supplied JavaScript, no broad directory read grant, and bundled assets only. A navigation delegate alone does not block subresources. Combine sanitization, content security policy, resource allowlisting and WebKit content rules; test remote CSS, images, SVG, frames, fonts, links, and redirects. WebKit's nonpersistent store concerns website data, not all operating-system caches. [WKWebsiteDataStore](https://developer.apple.com/documentation/webkit/wkwebsitedatastore), [WKContentRuleListStore](https://developer.apple.com/documentation/webkit/wkcontentruleliststore).

Mermaid, Vega, Lottie and notebook HTML are optional later renderers, not reasons to execute arbitrary content in the MVP. Never run notebook cells, MDX components, package scripts, LaTeX commands, diagram shell tools, or repository code to generate a preview.

## Dependency shortlist

The subsequent user requirements make [modular format extension](../decisions/001-format-extensibility.md) and [user-controlled file types](../decisions/002-file-type-controls.md) explicit acceptance contracts. Use small domain-owned contracts, injected lazy factories and catalog-driven settings. Stable format IDs, not decoder identities, own enablement; the shared core gates content work before parser construction. Enablement is independent of display-preference overrides. The root plan owns the refined target structure and implementation gates.

These are candidates, not installed packages or approved shipping revisions. License labels below are preliminary upstream declarations; inspect the pinned revision and all bundled grammars/transitive code before acceptance.

| Need | Candidate / source | Preliminary license and decision | Acceptance gate |
|---|---|---|---|
| Markdown syntax tree | [swiftlang/swift-markdown](https://github.com/swiftlang/swift-markdown) | Apache-2.0 declaration; inspect exceptions, notices and cmark dependency | GFM fixtures, resource caps, selection/accessibility in our renderer |
| Code highlighting | [tree-sitter/swift-tree-sitter](https://github.com/tree-sitter/swift-tree-sitter) | BSD-3-Clause wrapper; separate grammar licenses | Small initial language set, pinned C parser and grammars, bounded parse/query work, cancellation, Unicode offsets |
| Alternative highlighter | Bundled lexical tokenizer for a deliberately small set | Original code; avoids grammar startup but creates language-maintenance work | Compare correctness/latency with tree-sitter; never promise comprehensive syntax support from regex alone |
| YAML | [jpsim/Yams](https://github.com/jpsim/Yams) | Upstream states Yams and libYAML are MIT | Node-based display, aliases/depth/expansion budgets; unsafe documents fall back before materializing an enormous graph |
| TOML | [LebJe/TOMLKit](https://github.com/LebJe/TOMLKit) | MIT wrapper, toml++ license separately audited | C++ build/exception audit, typed dates, spec fixtures, Swift 6 build; text fallback until accepted |
| ZIP / ZIP64 | [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | MIT declaration | Central-directory listing, malformed sizes/offsets, ZIP64, encryption/split rejection; no extraction required for listing |
| TAR/GZIP and later archives | [libarchive](https://www.libarchive.org/) with a narrow pinned build, or format-specific readers | BSD-style upstream license; enabled codecs separately audited | List-only API, bounded input/output and cancellation, macOS SDK/library availability checked; no reliance on shell `tar` |
| SQLite | Public `sqlite3` C interface in macOS SDK | System library initially; version varies with OS | Security options actually supported on minimum OS, WAL and sandbox behavior, safe identifiers, read-only behavior |
| Plists, XML, CSV, environment, JSONL | Foundation plus small focused parsers | No new runtime dependency for straightforward cases | Disable XML external entities; encoding, huge-line, malformed-record and limit tests |
| MIDI/audio/images/certificates | Public Apple frameworks | No third-party codec in baseline | Device and sandbox feasibility tests; supported subtype list must be explicit |

Do not ship both ZIPFoundation and a broad libarchive build merely because both exist. First benchmark ZIPFoundation for ZIP and the smallest TAR/GZIP option; consolidate only when correctness, binary size and maintenance improve. Keep XIP as a separately validated composite reader task. An Xcode-style XIP can expose only Metadata and Content in the outer XAR table; finding actual inner paths requires bounded PBZX decompression and CPIO scanning. XAR support alone does not establish full XIP file listing. Listing without writing extracted files still involves decompression and potentially substantial CPU/I/O; stop at the shared budget and label the partial result. Signature verification is a separate capability and is not claimed. [unxip's implementation/design](https://github.com/saagarjha/unxip).

For tree-sitter, the wrapper documentation explicitly treats language parsers as separate projects. Bundling a grammar is a code distribution decision; user theme imports must remain inert data, not grammar libraries or scripts. [SwiftTreeSitter](https://github.com/tree-sitter/swift-tree-sitter).

## Concurrency and lifecycle

The initial workspace has **no** `Package.swift` or `.pbxproj`; there are no existing language/isolation settings to infer. Local inspection found Command Line Tools selected and Swift reporting version 6.4, but no `Xcode*.app` in `/Applications`. This is environment evidence only, not a release recommendation or proof that a full Xcode installation cannot exist elsewhere.

Proposed configuration at scaffold time: Swift 6 language mode, complete concurrency checking, explicit UI `@MainActor` boundaries, and non-main-isolated parser/library targets. Record default actor isolation and upcoming-feature flags explicitly. Pin a supported toolchain and confirm its SDK can build the macOS 15 deployment target; do not inherit unexplained template defaults. This is a new-project choice, not migration guidance for unknown settings.

Swift's evolving isolation defaults mean `async` alone is not proof that CPU work leaves the UI actor. Use explicit non-UI execution boundaries supported by the chosen compiler (`@concurrent` where appropriate), structured tasks for bounded independent work, and cancellation checks between chunks. For potentially blocking file/library operations, use a small bounded worker queue or custom executor adapter rather than filling the cooperative executor with blocking calls. [Swift concurrency](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/concurrency/), [Swift 6.2 concurrency changes](https://www.swift.org/blog/swift-6.2-released/).

Each preview owns a request ID, file-access lifetime, immutable settings snapshot, cancellation token, deadline and budget ledger. A replaced request can never publish into the next request's view. Close descriptors, stop audio and release decoder state on teardown. A Swift timeout cannot forcibly stop a C parser: require a parser work hook, bounded input, or reject that parser for automatic previews until a viable isolation strategy is proven. Do not promise an arbitrary helper process or XPC service can be used from every extension context without prototyping it.

Serialize a SQLite connection on one worker owner; never pass it as unchecked Sendable. Expose immutable page results to the UI. Configure defensive/trusted-schema options, limits, progress interruption, and no extension loading. `mode=ro` and `immutable=1` have different meanings: immutable is only correct for an actually immutable input or validated snapshot, not a live database. WAL state and sidecar access can prevent a trustworthy preview; decline rather than silently show incomplete data. [SQLite security](https://www.sqlite.org/security.html), [SQLite URI parameters](https://www.sqlite.org/uri.html), [WAL read-only databases](https://www.sqlite.org/wal.html#read_only_databases).

The no-source-mutation contract includes the database and source-adjacent `-wal`, `-shm`, and journal files: no creation, write, deletion or checkpoint by preview work. Validate this with filesystem-operation tracing and before/after fixture inspection, not just a main-file hash. A coherent private snapshot is an option only after its consistency and authorized acquisition are proven; copying a live database and its sidecars at unrelated times is not sufficient. Decline live-WAL data browsing until this gate passes.

## Shared settings

Create a versioned `PreviewPreferences` value model and a single companion-app writer in an App Group. Atomic replacement of a small validated settings document is the preferred source of truth for rich theme data; an App Group defaults suite may hold simple flags. The extension reads a snapshot at each request and never needs the app process alive. Handle absent/corrupt/newer schemas with safe defaults. Do not treat notifications or `@AppStorage` as cross-process transactional synchronization.

Precedence: temporary preview override, renderer-family override, global preference, built-in default. In the first release only the companion persists changes; preview controls affect that preview. Store font descriptors and color/token data, never arbitrary CSS/JS. Defaults include semantic light/dark/high-contrast theme variants. Theme editing rerenders a bundled sample locally. New Finder previews pick up changes; existing OS thumbnails may remain cached and their refresh is not guaranteed.

## Performance budgets to validate

All numbers are **initial engineering targets**, not measured results, OS limits, or marketing claims. Recalibrate after P0 on a recorded baseline Mac, then commit the selected limits as testable policy. Budgets must count work before allocation, not only truncate the final UI.

| Resource / observation | Initial policy |
|---|---|
| Ordinary text input | Read at most 2 MiB and display at most 20,000 lines; cap a rendered line at 32 KiB with an omission marker |
| Structured tree | At most 2 MiB input, depth 64, and 20,000 nodes; source fallback on limit or invalid structure |
| Archive listing / folder summary | At most 10,000 entries; folder default is direct children, no recursive traversal or symlink following |
| Archive work beyond entry count | At most 32 MiB cumulative compressed/source bytes read, 64 MiB cumulative decoded bytes scanned, 8 MiB ZIP central-directory bytes and 4 MiB aggregate names/metadata; enforce during reads/decoder callbacks |
| Expanded archive member for optional embedded preview | At most 8 MiB actual output, ratio check and shared cumulative budget; no recursive nested preview by default |
| SQLite | Page 200 rows, at most 50 columns and 4 KiB per cell, initially 250 ms statement work budget and 1 s total initial preview work budget |
| Heavy parsing | Check deadline/work counters; 1 s soft deadline to useful fallback; cap parser work independently of wall clock |
| Warm preview first useful content | Target p95 ≤200 ms on local ordinary fixtures up to 256 KiB |
| Cold extension first useful content | Target p95 ≤700 ms, measured separately from Finder-owned scheduling |
| Text scroll responsiveness | Target a 60 Hz frame budget without sustained main-thread stalls; report p95 UI update time |
| Memory | Initial target ≤100 MiB peak incremental footprint per ordinary native preview; report absolute footprint and input size too |
| Cancellation | Target no stale result publication and resource release within 100 ms for cancellable local work; blocking/provider latency reported separately |

Measure ten cold invocations and at least fifty warm invocations per representative renderer during the spike; expand samples where variance makes p95 unstable. Include extension launch cost, file-access wait, parse, highlighting, layout, first visible content and total work as separate `os_signpost` intervals. Measure Release builds for the performance requirement, with optimization/settings recorded. Use Instruments, Allocations/VM tracking, Time Profiler and hangs; simulator or package-only timings do not validate Finder behavior.

Adversarial fixtures: huge single lines, deep nesting, aliases, malformed UTF-16, Unicode combining sequences and RTL/bidi controls, JSON precision/duplicate keys, archive bombs/path traversal, encrypted and split archives, external-entity XML, malicious Markdown links, changing/truncated files, unavailable cloud placeholders, symlink cycles, and locked/live WAL databases. A resource cap test must verify the cap precedes large allocation and that fallback remains responsive.

A compressed TAR/GZIP/XIP can spend enormous work before reaching its second entry. Test a one-entry decompression bomb and an oversized ZIP central directory; entry count and a UI timer alone do not bound either case. Partial-list UI must distinguish a complete index from the entries reached before a scan budget expired.

## Build and distribution strategy

Planned boundaries: `PrevApp`, `PrevPreviewExtension`, `PrevThumbnailExtension`, `PreviewCore`, `PreviewRenderers`, `PreviewPreferences`, and test fixtures. Shared modules must use extension-safe public APIs; platform UI adapters remain outside pure parsing models. Add only modules justified by boundaries rather than one package per file format.

Once targets exist, run `swift test --package-path Packages/PreviewCore` for core behavior; use `xcodebuild` for app/extension integration and a signed installed build for Finder checks. Package libraries are not directly runnable with `swift run`. Create the repository build/run script and Codex environment file only during the scaffold phase, using the macOS build skill's bootstrap contract.

Mac App Store rules require sandboxing and Xcode packaging and constrain runtime downloads and background processes. Therefore ship bundled parsers, no self-updater in the Store build, no login agent requirement, no private APIs, and no runtime installation of preview plugins. Validate entitlements, privacy manifests/reasoned API use, dependency notices, minimum OS and clean-install behavior before submission. App Review acceptance remains a future external decision. [App Review Guidelines §2.4.5 and §2.5](https://developer.apple.com/app-store/review/guidelines/).

## Decisions requiring a prototype

- [ ] Prove signed preview and thumbnail invocation with the companion quit.
- [ ] Compare text layout/highlighting and Markdown selection/accessibility alternatives on the same corpus.
- [ ] Pin and audit parser revisions, grammar licenses, extension API safety and binary size.
- [ ] Prove cancellability or hard bounded work for each parser; verify no source writes and no document-triggered network requests.
- [ ] Prove atomic preferences updates across separate app/extension processes and fallback after corruption.
- [ ] Measure the budgets above on macOS 15 and the supported current macOS, with Apple silicon and Intel coverage if Intel remains a shipping target.
- [ ] Decide the final XIP/WAL/MIDI interaction contracts based on Finder-hosted prototypes rather than generic framework availability.
