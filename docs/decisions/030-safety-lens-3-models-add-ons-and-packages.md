# Decision 030 — Safety Lens 3: model files, add-ons and packages

Date: 2026-10-14. Status: accepted at the owner's request ("Continue development", after the list that recommended this set as the next step). Implementation in progress; this record states the contract and the rules each feature follows.

## Context

[Decision 029](029-safety-lens-2-what-a-file-will-do.md) answered "what will this file do?" for scripts, configuration, exports, launchd jobs and certificates. The [2026-10-13 research](../market/2026-10-13-new-file-types-and-features.md) left three tier-A candidates open, each with no Quick Look tool found:

- **A5, AI model files.** GGUF and safetensors files are opaque in Finder; Python pickles and PyTorch checkpoints can run code when loaded (nullifAI, ReversingLabs, February 2025).
- **A3, bundle and extension cards.** MCP bundles, VS Code extensions and browser extensions run with the user's rights; GlassWorm hid code in invisible characters in VS Code extensions.
- **A4, install-time package lens.** npm tarballs and Python packages can run code on install (Shai-Hulud, Phantom Gyp, the LiteLLM `.pth` file).

Each candidate is a new format that existing parsers already half cover: the ZIP reader, the TAR and gzip readers, the summary writer and the findings contract.

## Decision

### New formats

| Format ID | Suffixes | Container | Type declaration |
|---|---|---|---|
| `ml.gguf` | `.gguf` | GGUF header | imported `org.webmeister.spacepane.type.gguf`, conforms to `public.data` |
| `ml.safetensors` | `.safetensors` | 8-byte length and a JSON header | imported `org.webmeister.spacepane.type.safetensors`, `public.data` |
| `ml.pickle` | `.pt`, `.pth`, `.ckpt`, `.pickle`, `.joblib` | PyTorch ZIP, raw pickle, or a text `.pth` path file | imported `…type.pytorch` (`.pt .pth .ckpt`) and `…type.pickle` (`.pickle .joblib`), `public.data` |
| `package.mcp-bundle` | `.mcpb`, `.dxt` | ZIP with `manifest.json` | imported `…type.mcp-bundle`, conforms to `public.zip-archive` |
| `package.editor-extension` | `.vsix` | ZIP with `extension/package.json` | imported `…type.vsix`, `public.zip-archive` |
| `package.browser-extension` | `.xpi`, `.crx` | ZIP, or a CRX3 header and a ZIP | imported `…type.xpi` (`public.zip-archive`) and `org.chromium.extension` (`public.data`) |
| `package.python-wheel` | `.whl` | ZIP with a `.dist-info` folder | imported `…type.python-wheel`, `public.zip-archive` |

All suffixes except `.crx` resolve to dynamic types on macOS 27.2, so each needs an imported declaration, as `.apk` and `.npy` did. `.crx` is declared by Chrome as `org.chromium.extension`; the catalog imports that identifier, as it does `org.bittorrent.torrent`. `.pkl` is Apple's Pkl configuration language (`public.pkl-source`) and `.bin` is MacBinary; neither is claimed.

npm tarballs and Python source distributions stay `archive.gzip`. When the decoded TAR holds `package/package.json`, or a top folder with `PKG-INFO` and `setup.py`, the listing adds install-time findings. No new format, no new toggle.

Every new format presents a **summary** (decision 017's `SummaryWriter`, origin `.summary`), lists its archive members where it has them, is enabled and disabled like any other type, and has a **generic thumbnail**. A facts badge on thumbnails is later work.

### Findings

Twenty-two new kinds in six groups, each with a default severity in the contract and wording in `FindingText`:

| Group | Kinds | Producer |
|---|---|---|
| `artifact.*` | `nativeCode` (caution), `mismatchedContent` (caution) | any adapter below |
| `model.*` | `incomplete` (caution), `inconsistentLayout` (caution) | GGUF, safetensors |
| `pickle.*` | `runsCode` (warning), `networkOrFiles` (caution), `uncommonImports` (info), `brokenStream` (caution) | pickle scanner |
| `install.*` | `nativeBuild` (caution), `startupCode` (warning), `buildScript` (info), `remoteDependencies` (caution) | npm and Python packages, `.pth` files |
| `bundle.*` | `runsProgram` (info), `asksForSecrets` (info), `broadFolderAccess` (caution), `toolTextTargetsAssistant` (caution) | MCP bundles |
| `extension.*` | `startsAutomatically` (info), `installsOthers` (info), `allSites` (caution), `sensitivePermissions` (caution), `selfHostedUpdates` (caution), `relaxedScriptPolicy` (caution) | editor and browser extensions |

Existing kinds are reused where the fact is the same: `autorun.installScripts` for an npm tarball's lifecycle scripts; the `script.*` kinds when those scripts download and run, decode and run and so on (found by running `ScriptEffectsLens` over the script text); and the `hidden.*` kinds for invisible characters in a manifest, a tool description, a chat template or a bounded set of script members.

### Rules every adapter follows

Decision 029's rules hold: facts, not verdicts; conservative recognition; never execute, evaluate or decode-and-interpret; bounded and cancellable. In addition:

- **Header and manifest only.** Model readers touch the header and stop before tensor data; nothing proportional to the weights is read. Archive adapters read the central directory and a short, named list of members, each with a byte cap; nested archives are not opened.
- **A pickle is never loaded.** The scanner walks opcodes, keeps a memo of strings only to resolve `STACK_GLOBAL`, builds no objects and imports nothing. It is written from the Python documentation of the protocol; no code from picklescan, ModelScan or fickling (LGPL) is copied.
- **No all-clear.** No surface says a file is safe. A pickle summary states what was checked ("imports only; the file was never loaded"); a silent banner means only that nothing was found.
- **Summaries carry no lines.** Findings on a summary have empty `lines`. Document strings in a summary go through the summary writer's concealment, like every other summary value.
- **Content beats suffix.** `.pt`, `.pth` and `.ckpt` are sniffed: a PyTorch ZIP, a raw pickle, or, for `.pth`, a Python path file shown as text. A mismatch that matters is `artifact.mismatchedContent`.
- **Counts, not values.** A permission name, a host, a module name or a command may appear in the summary, which the user reads as the file's content; it never appears in a finding.

### Composition

`ModelFormatAdapters`, `AddOnFormatAdapters` and `InstallableFormatAdapters` each add one line to `StandardFormatAdapters`. Summary labels come from one `SummaryLabelSet` per family, registered on one line each in `SafeSchemaLabels`. A `.pth` path file is source text, so the `PythonPathFileLens` attaches to `ml.pickle` in `StandardLenses` and reports `install.startupCode` with lines; it never runs on the summaries.

`listingDocument` takes optional extra findings so the TAR listing can carry install-time findings next to its archive risks. This is the only shared-code change outside the contract.

### Localization

Finding wording is a typed `PreviewStrings` key with translator context in `tools/localization/additions/safety-lens-3.json`. Each workstream adds its summary labels below its own marker in `PreviewStrings.swift` and in its own additions file. All 14 chosen languages are drafts pending native-speaker review; version 1.0 ships English only.

## Feature boundaries

| Feature | Files | Owner (tools/ownership.json) |
|---|---|---|
| GGUF and safetensors | `PreviewFormats/Models/GGUF*`, `Safetensors*`, `SafeSchemaLabels+Models.swift` | `sl3-models` |
| Pickle and PyTorch scan, `.pth` path files | `PreviewFormats/Models/Pickle*`, `PyTorch*`, `Lenses/PythonPathFile*`, `SafeSchemaLabels+Pickle.swift` | `sl3-pickle` |
| MCP bundles, editor and browser extensions | `PreviewFormats/AddOns/**`, `SafeSchemaLabels+AddOns.swift` | `sl3-addons` |
| npm and Python packages | `PreviewFormats/Installables/**`, `Containers/TARListingAdapter.swift`, `SafeSchemaLabels+Installables.swift` | `sl3-install` |
| Finding wording in 14 languages | `tools/localization/additions/safety-lens-3.json` | `sl3-strings` |
| Contract, kinds, catalog, manifests, composition, samples, host matrix | — | lead |

## Consequences

- Seven formats join the catalog; the website reads it, so `npm run data:sync` runs in `spacepane-web` when this reaches `main`.
- None of this changes which provider macOS picks. Model files and these packages have no system previewer on macOS 27.2, so routing is expected to reach SpacePane, but that needs a Quick Look observation like decision 029's.
- Findings describe declared behaviour. A static card cannot see code that changes later (a sleeper extension) or code with no install hook (the chalk and debug compromise of September 2025); the documentation says so.

## Validation

Each adapter has synthetic fixtures built in test code: a normal file, near misses that must stay silent, malformed and truncated input, an oversized header, cancellation, and the summary's privacy (a token-like string in metadata is concealed). Pickle fixtures are opcode bytes assembled by hand; no fixture is produced by pickling a live object, and none is ever loaded. Finder-hosted rendering, VoiceOver review and native-speaker review stay open.

## Implementation notes — 2026-10-14

Recorded at integration of branch `safety-lens-3`; each point narrows or completes a rule above.

- **GGUF.** Versions 2 and 3 in either byte order; version 1 and later versions are `unsupportedVariant`. The header is read in windows of 64 KiB growing to 1 MiB, so at most one window past the header is fetched and discarded. When the 16 MiB read budget ends inside the metadata (a very large vocabulary), the summary is marked partial and carries no totals and no incomplete-download finding. The alignment must be a power of two. `model.incomplete` counts tensors that end beyond the file; `model.inconsistentLayout` counts overlaps, unaligned offsets and first dimensions that are not whole blocks.
- **safetensors.** A strict scanner for the one schema: 16 MiB header, 200,000 tensors, depth 4; duplicate keys, non-integer numbers, bad escapes and invalid UTF-8 are malformed. `model.inconsistentLayout` also covers a byte range that does not match the dtype and shape, and bytes after the last tensor. A shard's position is two integers, `shardIndex` and `shardCount`.
- **Pickles.** Unknown binary content under these suffixes is `unsupportedFormat`; a 7z, GGUF, safetensors, HDF5 or NumPy file, or a ZIP with no pickle member, gets its container name and `artifact.mismatchedContent`. A `.pth` file that is a complete pickle is scanned, not shown as text; an empty file is malformed. A `STACK_GLOBAL` whose module or name the walker cannot resolve to a literal string counts as an uncommon import, so an obfuscated import can stay at info level: a known limit of a static scan, which the "imports only" line already states. joblib array wrappers end the scan as partial, because raw array bytes follow them. The classification lists in `PickleImports.swift` extend the brief with debuggers, profilers, `pip`, `pydoc`, `numpy.f2py`, other pickle loaders (dill, cloudpickle, joblib, pandas) and `torch.hub.load` as able to run code.
- **Add-ons.** List fields are cut to 32 items. A Manifest V3 `sandbox` policy may contain `unsafe-eval` without a finding, because Chrome allows it only there. A CRX header is skipped, never parsed, so no extension ID is shown; a `.crx` without one is read as a plain ZIP. Script members are read as prefixes (256 KiB each, 2 MiB in all, entry points first, `node_modules` last). Tool-text recognition is English only.
- **npm and Python packages.** The TAR listing captures members only on the decoded path (`.tar.gz`, `.tgz`, `.tar.bz2`, `.tar.xz`); a plain `.tar` is listed as before. The npm lifecycle names are the same list the `package.json` lens uses. `"gypfile": false` suppresses `install.nativeBuild`. A `.pth` file whose name starts with a dot is not counted, because current CPython skips such files. A wheel with more than 10,000 members fails with the shared ZIP limit.
- **Presentation.** MCP bundles, extensions and wheels open in Summary, ahead of Files, like the other packages (`SafeSchemaLabels.summaryFirstListings`).
- **Strings.** 22 finding keys, 14 format-name keys and 98 summary-label keys in 14 languages, drafts pending native-speaker review.
