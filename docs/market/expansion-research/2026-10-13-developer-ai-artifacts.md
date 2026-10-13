# Developer, DevOps, security and AI/ML artifacts: new file types for SpacePane

Researched 2026-10-13 (Europe/Istanbul). Angle: developers, DevOps/SRE, security engineers and ML/AI practitioners, new TYPES only. Builds on [the competitor landscape](../2026-10-05-competitor-landscape.md) and [unique feature opportunities](../2026-10-05-unique-feature-opportunities.md).

## Method and limits

Evidence labels used throughout:

- **(V)** verified: I opened the primary source (page, spec, repository, App Store listing), queried the GitHub API on 2026-10-13, or inspected a file on the development Mac (macOS 27.2).
- **(VC)** vendor claim: from a vendor's own listing or marketing, not tested.
- **(S)** search summary only: seen in a web-search result summary; I did not open the page.
- **(I)** my inference or proposal.

What I did:

- Read the 74-type catalog (`FormatCatalog.json`), AGENTS.md, decisions 017/025 and the prior market documents so nothing already shipped is re-proposed.
- Asked macOS which of ~120 candidate suffixes already have a system type declaration and whether that type conforms to `public.text` (Swift `UTType`, run locally). Caveat: the dev Mac has third-party apps installed that also declare types (for example `org.duckdb.duckdb-database`, `com.proxyman.nsproxy.har`), so "declared" does not always mean "declared by macOS itself".
- Opened primary sources for GGUF, safetensors, pickle scanning, Mach-O/code-signing headers, the TFLite schema, OpenSSH key format, Terraform state docs, the LookQuick App Store page, the Unfold changelog and the Library Inspector listing. Pulled stars and licences for ~50 repositories through `gh api`. Counted Hugging Face models per library from the Hub's own listing pages.
- Inspected, keys only, one local `.ips` crash report, one Claude Code transcript and one Codex rollout file to check the schemas against reality.

Limits you should weigh:

- **The iTunes Search API sweep the brief asked for was not completed.** The first request worked; every later request (including from `curl` with the default user agent, after pacing and long back-off) returned HTTP 403. Competitor coverage below therefore comes from web searches ("<format> quick look mac"), the LookQuick App Store page, the Unfold changelog, the existing landscape documents and a grep of earlier research notes. I could not scan the full set of Mac App Store descriptions, so "no Quick Look app found" means "none found by these methods". Re-run the sweep before committing to any of the top picks.
- No parser was built, fuzzed or timed. Effort labels (S = days, M = 1 to 2 weeks, L = several weeks, each including localization, fixtures and thumbnails policy) are estimates.
- Finder routing for new suffixes, extension behaviour on iCloud "dataless" files and Quick Look host time and memory limits for multi-gigabyte files are unverified (I).
- GitHub star counts are from the API on 2026-10-13. Hugging Face counts are the number of Hub models tagged with each library, on the same day; they count models, not files.

## Key findings

1. **No Quick Look app found claims any AI model format.** Searches for GGUF, safetensors, ONNX, PyTorch checkpoints returned no Quick Look app (S), LookQuick's listing names none of them (V), and Unfold's last eight releases mention none (V). The Hub tags 211,263 GGUF, 1,420,603 safetensors, 255,245 PyTorch, 56,555 ONNX and 26,044 MLX models (V). A header-only read answers what people actually ask of such a file: architecture, parameters, quantisation, context length, chat template, licence, "did my download finish?". This is the strongest "new type" family for the AI-era positioning.
2. **A pickle-import scan fits the Safety Lens exactly and the prior art shows how to do it and how not to.** Hugging Face itself shows the import list of every pickle on the Hub (V). Denylist scanners were bypassed repeatedly in 2025: nullifAI (malformed or non-ZIP pickles), three picklescan zero-days fixed in 0.0.31 (extension mismatch, ZIP CRC, subclass imports), earlier extension and ZIP-flag bypasses, and `torch.load(weights_only=True)` RCE in PyTorch 2.5.1 and earlier (S, all). The design that survives this: show an inventory of every imported callable, never claim "safe", treat a malformed stream as a finding and ignore file extensions. The one mature scanner with a decompiler, fickling, is LGPL-3.0 (V) and cannot be used; picklescan (MIT) and ModelScan (Apache-2.0) are prior art to read, not dependencies to ship.
3. **Mach-O and library inspection is an open lane on macOS 15+.** The only Quick Look product I found is Library Inspector, last updated 2016, macOS 10.9+, a legacy plug-in generation (V: App Store page). LookQuick's listing names `.exe`, `.dll` and `.reg` but not Mach-O (V). SpacePane's `.app` adapter already reads a Mach-O header, so extending to `.dylib`, `.o`, `.a`, frameworks, XPC services and `.dSYM` is the cheapest large step for Mac developers, and Apple's `cs_blobs.h` and `loader.h` publish the code-signature and load-command layouts (V).
4. **Crash reports are text to macOS already, so the case rests on a digest.** `.ips`, `.crash`, `.spin` and `.hang` resolve to system types that conform to `public.text` (V, local UTType check), so Finder shows raw text (I). A local `.ips` confirms the layout: line 1 is a 13-key JSON header, the rest is a body with ~56 keys including `exception`, `termination`, `threads`, `usedImages`, `faultingThread` (V). A "what happened" digest plus a Copy Redacted action (the report carries `procPath`, `userID`, `bootSessionUUID`) is a clear evidenced gain under constraint 4.
5. **Agent transcripts have the loudest demand and the least stable format.** Viewers for them have 22,412 (opcode, AGPL), 2,246, 1,700 and 1,296 stars (V). One local Claude Code file had 13 record types and over 90 distinct top-level keys; a Codex rollout used an unrelated schema (`session_meta`, `event_msg`, `response_item`) (V, local). A tolerant mapper that degrades unknown records to one-line stubs is mandatory, and the view needs a new Conversation presentation (shared-contract change).
6. **A unifying theme is available: "what does this file want?"** Entitlements and linked libraries for binaries, imported callables for pickles, WASI imports for WebAssembly, commands run in agent sessions, cleartext credentials in captures, embedded sources in source maps, environment and history in container images, plaintext secrets in Terraform state. It extends the Safety Lens from "what is hidden in this text" to "what can this file do or expose", and it needs nothing outside the sandbox.
7. **Much of the work reuses code that already exists.** A bounded protobuf wire reader (written for AAB manifests) serves ONNX, pprof, raw `.pb` and Core ML. The bounded ZIP reader serves PyTorch zips and `.keras`. The TAR reader serves OCI images. The JSON/JSONL readers serve source maps, SARIF, fine-tuning data and transcripts. The CMS and SecCertificate paths from decision 017 serve code-signing certificates.
8. **Suggested order** (I): safetensors and GGUF together (shared Tensors table), pickle scan, source maps and WebAssembly (both S), Mach-O and crash digest, then transcripts, capture summaries and container images.

## Ranked candidates

Competitor column: "none found" = none found by web search and the sources listed in Method; naming a product means its vendor claims it (VC). Effort: S = days, M = 1 to 2 weeks, L = several weeks.

| # | Candidate (suffixes) | Audience | macOS native today | Quick Look competitor coverage | Route + licence | Reuses which presentation | Effort | Verdict |
|---|---|---|---|---|---|---|---|---|
| 1 | Model weights: GGUF (`.gguf`), safetensors (`.safetensors`, plus `model.safetensors.index.json`) | Local-LLM users, ML engineers, LoRA/ComfyUI collectors | None: dynamic types only (V) | None found | Header-only own parsers from public specs; ggml MIT, safetensors Apache-2.0 (reference only, nothing linked) | Summary header, sortable Tensors table, metadata outline, template as source text, findings banner | M | **Lead with** |
| 2 | PyTorch and pickle checkpoints (`.pt .pth .ckpt .bin .pkl .pickle .joblib`) import scan | ML engineers, security | `.pkl` is typed `public.pkl-source` (Apple's Pkl configuration language), which conforms to text, so a Python pickle named `.pkl` is typed as text (V UTI; rendering not tested); the other suffixes are dynamic (V) | None found | Own opcode walker from CPython pickle docs, never unpickles; picklescan MIT and ModelScan Apache-2.0 as reading material; fickling LGPL excluded | Summary, Imports table, findings banner, Files (zip members) | M | **Lead with** |
| 3 | Agent session transcripts and chat exports (Claude Code and Codex `.jsonl`, OpenAI-style chat JSONL, ChatGPT/Claude `conversations.json`) | AI-tool users, security reviewers | JSONL previews as text (V) | Partial: QLook JSON lists "JSONL for AI-agent logs" (VC); no conversation view found | Own tolerant mappers over the existing JSONL reader; no dependency | New Conversation mode plus Summary, Actions table, findings | L | **Lead with** (accept volatility) |
| 4 | Mach-O binaries and libraries (`.dylib .o .a .so`, frameworks, `.xpc`, `.appex`, `.dSYM`; siblings ELF and PE) | Mac developers, security | `.dylib`, `.o` declared as data (V); `.a`, `.so` dynamic; no preview beyond file info (I) | Library Inspector (2016, legacy, V); LookQuick `.exe`/`.dll` only (V); `.app`-level signing in Unfold and LookQuick (VC) | Own parser from public loader and code-signing headers; MachOKit MIT as a reference only | Summary, Libraries table, Segments table, entitlements outline, findings | M | **Lead with** (for Mac developers) |
| 5 | Crash and diagnostic reports (`.ips .crash .spin .hang .diag`) | App developers, support engineers | Conform to `public.text`, so plain text (V UTI, I rendering) | None found | JSON and text parsing; no dependency | Summary, Threads outline, Images table, findings, Copy Redacted | M | **Add** |
| 6 | Packet captures (`.pcap .pcapng`) | Network and security engineers | None (dynamic, V) | Cocoa Packet Analyzer has a legacy plug-in (VC); TCP Viewer is a standalone app; none for current macOS found | Own readers from the IETF pcap and pcapng drafts; no dependency | Summary, Conversations table, Names table, findings | L | **Add** |
| 7 | JavaScript source maps (`.map`, `*.js.map`, `*.css.map`) | Web and Node developers, security | None (dynamic, V) | JSON Loupe handles `.map` as JSON (VC) | JSON; spec ECMA-426 (S); no dependency | Summary, Files/Tree of sources, source text, findings | S | **Add** |
| 8 | Container image tarballs (`docker save`, OCI layout `.tar`) and Helm charts (`.tgz`) | DevOps, SRE, security | `.tar` listed by SpacePane today; `.tgz` declared as a gzip tar archive (V) | None found | Existing TAR reader plus JSON; OCI image-spec Apache-2.0 (reference) | Summary, Layers table, Env outline, findings, Files | M | **Add** |
| 9 | WebAssembly modules (`.wasm`) | Rust, Go, Zig and plug-in developers | None (dynamic, V) | None found | Own section reader from the WebAssembly spec; wabt Apache-2.0 and wasm-tools Apache-2.0 as references | Summary, Imports/Exports tables, Sections table, findings | S to M | **Add** |
| 10 | ONNX models (`.onnx`) | ML engineers | None (dynamic, V) | None found | Existing bounded protobuf wire reader over `onnx.proto` (Apache-2.0) | Summary, Op histogram table, Inputs/Outputs table, metadata outline | M | **Add** |
| 11 | Keras v3 archives (`.keras`); legacy `.h5` out | ML engineers | None (dynamic, V) | None found | Existing ZIP reader plus JSON; Keras Apache-2.0 (reference) | Summary, Layers table, findings | S | **Add** |
| 12 | TFLite (`.tflite`), Core ML (`.mlmodel`, `.mlpackage`, `.mlmodelc`) | Mobile and Apple-platform ML developers | Core ML types are declared (data, dir) (V); Xcode has its own model viewer (I); `.tflite` dynamic | None found | FlatBuffers vtable reader (TFLite, Apache-2.0 schema); protobuf (Core ML, coremltools BSD-3-Clause) | Summary, I/O table, op histogram | M each | Niche |
| 13 | Keys and identities: OpenSSH keys and `authorized_keys`/`known_hosts`, PGP/GPG, CSR, CRL, JWT/JWK, Java keystores | Developers, DevOps, security | `.p12`/`.pfx`, `.pem`, `.der` declared; `.csr .crl .jks .asc .gpg .pgp .jwt .jwk .pub` dynamic (V) | Super Quick Look names PEM/key files, `authorized_keys`, `known_hosts` (VC) | Own parsers (OpenSSH format, OpenPGP packets, DER walker); Security framework for certificates | Summary, entries table, findings | M | **Add** |
| 14 | Profiles and flame graphs (`.pprof`, `.cpuprofile`, speedscope JSON, folded stacks) | Backend, Go, Node and performance engineers | None (dynamic, V) | None found | Existing protobuf reader plus gzip; `profile.proto` Apache-2.0 | Top-functions table plus new flame-graph view | M to L | **Add** |
| 15 | Report digests: SARIF, CycloneDX, SPDX, JUnit XML, lcov, Cobertura | CI, security, compliance | `.sarif`, `.spdx`, `.cdx`, `.lcov` dynamic (V) | None found | JSON and XML dialect sniffing; specs public (CycloneDX Apache-2.0) | Summary, Results table | S each | Niche |
| 16 | Binary JSON family (`.msgpack .cbor .bson .ion`) and raw protobuf (`.pb .binpb`) | Backend and IoT developers | Dynamic (V) | None found | Own bounded decoders from RFC 8949 and the other public specs | Outline/tree plus JSON source | S to M | Niche |
| 17 | Fine-tuning and eval dataset JSONL check (OpenAI chat, ShareGPT, Alpaca, DPO shapes) | ML practitioners | JSONL previews as text (V) | None found | Existing JSONL reader; no dependency | Summary, findings (notebook-health-check pattern) | S | **Add** (overlaps the features agent) |
| 18 | Terraform state (`.tfstate`, `.tfstate.backup`, plan JSON) | DevOps, security | JSON text | Super Quick Look names HCL source only (VC) | JSON; no dependency | Summary, Resources table, findings | S | Niche |
| 19 | Xcode artifacts: `.xcarchive`, `project.pbxproj`, `.xcactivitylog` | Apple-platform developers | `.xcarchive` is a directory type, `.pbxproj` conforms to text, `.xcactivitylog` dynamic (V) | LookQuick names xcarchives and Xcode projects (VC) | Existing app adapter; XCLogParser Apache-2.0 as format reference | Summary, outline | S to M | Niche |
| 20 | JVM, Android, Python build outputs (`.class`, `.dex`, `.pyc`) | Java, Android, Python developers | `.class` and `.pyc` declared as data (V); `.dex` dynamic | None found | Own readers from public specs | Summary, References table | S each | Niche |
| 21 | Dataset and index headers: TFRecord, WebDataset shards, FAISS | ML engineers | Dynamic (V) | None found | Own framing readers; FAISS MIT, TensorFlow Apache-2.0 (references) | Summary, sample records | S each | Niche |
| 22 | Redis RDB, Git bundles | SRE, developers | Dynamic (V) | None found | Own readers from public format notes | Summary, key list | S each | Niche |

## Candidate sections

### 1. Model weights: GGUF and safetensors (Lead with)

**What the preview shows**

- **Summary** (GGUF): name, architecture, parameter count (exact: the sum of tensor element counts from the tensor table), dominant quantisation (from `general.file_type` plus a per-type tally of tensors, with average bits per weight), file size, context length, layers, embedding width, head and KV-head counts, vocabulary size, licence (`general.license`, an SPDX expression), base model and provenance (`general.base_model.*`, `general.source.*`), who quantised it, GGUF version and alignment. Key names inside `<arch>.*` are my inference of the llama.cpp convention; the `general.*` keys and file layout are from the spec (V).
- **Summary** (safetensors): tensor count, total parameters, dtype histogram (for example 99.9% BF16), shard position from the filename (`model-00002-of-00005`), tensors with sub-byte or FP8 dtypes, LoRA detection by tensor names (`lora_A`/`lora_B`, `lora_down`/`lora_up`, `.alpha`) with rank taken from shapes, and quantisation hints (`qweight`/`scales`/`g_idx` for GPTQ-style packing). The `__metadata__` map is shown as an outline. Stable Diffusion LoRAs written by kohya's sd-scripts store `ss_*` and `modelspec.*` training metadata (base model version, network dimension, learning rate, tag frequency) (S: [CivitAI article](https://civitai.com/articles/24796), [sd-scripts ModelSpec page](https://deepwiki.com/kohya-ss/sd-scripts/11.4-model-metadata-and-sai-modelspec)), so a preview can say "SDXL LoRA, rank 32" for files that Finder shows only as names.
- **Tensors mode**: sortable and filterable table (name, shape, type, elements, bytes), grouped by block index. **Metadata mode**: key/value outline with large arrays collapsed to "tokenizer.ggml.tokens: 128,256 strings". **Template mode** (GGUF): `tokenizer.chat_template` as highlighted source with the existing hidden-character scan.
- **Findings** (typed, no values): hidden Unicode in any metadata string or the template; the template reads message text rather than just roles (informational only: some reasoning-model templates legitimately test for `</think>`); tensor offsets beyond the file size, which is the partial-download case ("file is 12.1 GB, header describes 19.8 GB") (I); overlapping or non-contiguous safetensors ranges; header counts beyond bounds; duplicate keys.
- **Thumbnail**: a facts badge ("8B Q4_K_M", "LoRA r32") drawn from the summary, no weights or text from the file. This lets a folder of forty `.gguf` files be told apart in icon view (I).
- **Folder summary** (extension of the existing folder adapter): a directory with `config.json` plus `*.safetensors` shards and an index file gets a model summary, using `model.safetensors.index.json` (`metadata.total_size`, `weight_map`) (I; format known from the Hub convention, not re-opened).

**Demand evidence**

- Hub models by library on 2026-10-13: [GGUF 211,263](https://huggingface.co/models?library=gguf), [safetensors 1,420,603](https://huggingface.co/models?library=safetensors), [MLX 26,044](https://huggingface.co/models?library=mlx) (V). MLX weights are safetensors, so they are covered at no extra cost.
- Runtime popularity: [llama.cpp 131,066 stars](https://github.com/ggml-org/llama.cpp), [Ollama 183,027](https://github.com/ollama/ollama), [LocalAI 49,512](https://github.com/mudler/LocalAI) (V).
- Prior art proves the questions: the Hub ships a [GGUF viewer for metadata and tensors (name, shape, precision)](https://huggingface.co/docs/hub/gguf) (V); [gguf-parser-go](https://github.com/gpustack/gguf-parser-go) (MIT, 306 stars) estimates memory use (V); [Netron](https://github.com/lutzroeder/netron) (MIT, 33,568 stars) is the standard graph viewer (V). None of these runs in Finder.
- Security relevance: Pillar Security showed GGUF chat templates can carry inference-time backdoors that trigger on phrases in user input, validated on 18 models across 4 engines (S: [Pillar](https://www.pillar.security/blog/llm-backdoors-at-the-inference-level-the-threat-of-poisoned-templates), [arXiv 2602.04653](https://arxiv.org/pdf/2602.04653v3)). Pillar sells a product here, so treat prevalence claims with care. Displaying the embedded template, which the Hub page does not, is the defensible use.

**Implementation route**

- GGUF: [spec](https://github.com/ggml-org/ggml/blob/master/docs/gguf.md) (V). Layout is magic `GGUF`, `uint32` version (3 is current, adds big-endian), `uint64` tensor count, `uint64` metadata count, typed key/value pairs (arrays may nest), tensor infos (name up to 64 bytes, up to 4 dimensions, `ggml_type`, offset), then alignment padding and data. Tensor infos come after all metadata, so the reader must walk the vocabulary arrays (up to a few hundred thousand strings) to reach them. Reading is sequential from offset 0 and stops before tensor data. Suggested bounds (I): 32 MiB header window, 100k tensors, 10k keys, 1 MiB per string; arrays keep a count and the first 16 elements.
- safetensors: [spec and README](https://github.com/huggingface/safetensors) (V). 8-byte little-endian header length, JSON header that must start with `{`, optional `__metadata__` string map, per-tensor `dtype`, `shape` and `data_offsets` relative to the byte buffer, no holes, no duplicate keys, 100 MB header cap. Cap lower (16 MiB, I).
- Licences: format specs only, no code copied or linked. ggml [MIT](https://github.com/ggml-org/ggml/blob/master/LICENSE), safetensors [Apache-2.0](https://github.com/safetensors/safetensors/blob/main/LICENSE) (the repository now lives under the `safetensors` organisation), huggingface.js [MIT](https://github.com/huggingface/huggingface.js/blob/main/LICENSE) (V via GitHub API).
- Registration: both suffixes resolve to dynamic types here (V), so each needs an app-declared imported type like `.apk` and `.torrent` did.

**Safety and privacy**: metadata strings can hold author names, emails, URLs and local paths from conversion scripts, so they pass through the shared concealment pipeline; the template is inert text; no tensor values are read, so no weights are exposed; thumbnails carry facts only.

**Risks and unknowns**: new architectures add `<arch>.*` keys monthly, so the summary needs a raw-keys fallback rather than a closed schema; GGUF v1/v2 and big-endian files are rare but exist; whether reading a header from an iCloud dataless or network file triggers a full download is unverified; no timing data exists for 50 GB files on slow external disks.

### 2. PyTorch and pickle checkpoint scan (Lead with)

**What the preview shows**

- **Content-based type detection**, never trusting the suffix: PyTorch zip (entries ending `data.pkl`), legacy raw pickle, plain pickle misnamed `.bin`/`.pt`, a safetensors or 7z file hiding behind a `.bin` name. The mismatch itself is a finding.
- **Summary**: container kind, pickle protocol, number of storage entries and total tensor bytes (from zip entry sizes, nothing decompressed), number of pickles inside, `.npy` object-array check (NumPy `.npy`/`.npz` files with object arrays embed a pickle; (I), extends the existing NumPy adapter).
- **Imports table**: every `GLOBAL`, `STACK_GLOBAL`, `INST` and `OBJ` target as `module.name` with an occurrence count, classified Expected (tensor rebuild helpers, storage classes, `collections.OrderedDict`, NumPy array reconstruction), Uncommon (everything else; full-model pickles and scikit-learn/joblib files land here legitimately) or Execution-capable (`builtins.eval/exec/compile/__import__/open/getattr`, `os.*`, `posix.*`, `subprocess.*`, `socket.*`, `shutil.*`, `ctypes.*`, `runpy.*`, `importlib.*`, `pty.*`, `webbrowser.*`, `pickle.loads`, `torch.utils.collect_env.run` and similar).
- **Findings**: execution-capable import present ("loading this with `torch.load` or `pickle.load` can run code"); stream malformed after offset N with N imports seen before it (the nullifAI pattern); suffix/content mismatch; ZIP CRC errors that PyTorch would tolerate; duplicate member names; more than one pickle. A standing line: "Imports are the only thing checked. A file with no findings can still be unsafe. It was never loaded."
- Arguments passed to execution-capable calls are not displayed by default (they are indicators of compromise and often contain addresses); only module and name are. Whether to offer them behind a toggle is an open product call (I).

**Demand and incident evidence**

- Hugging Face scans every pickle upload and shows the import list, and states the scan is not foolproof ([HF docs](https://huggingface.co/docs/hub/security-pickle), V). PyTorch-library models on the Hub: [255,245](https://huggingface.co/models?library=pytorch) (V).
- 2025 incidents: ReversingLabs' nullifAI, two models using 7z and deliberately broken pickles to evade picklescan ([The Hacker News](https://thehackernews.com/2025/02/malicious-ml-models-found-on-hugging.html), [Wiz](https://threats.wiz.io/all-incidents/malicious-ai-models-bypass-picklescan-detection)); JFrog's three picklescan zero-days, reported June 29 and fixed in 0.0.31 on September 2, 2025 ([JFrog](https://jfrog.com/blog/unveiling-3-zero-day-vulnerabilities-in-picklescan/)); CVE-2025-1889, -1944, -1945 earlier; CVE-2025-71350 for `torch.utils.collect_env.run` (single-source, unconfirmed); [CVE-2025-32434](https://osv.dev/vulnerability/CVE-2025-32434), `torch.load(weights_only=True)` RCE in PyTorch 2.5.1 and earlier, fixed in 2.6.0 (S, all).
- Prior art licences: [picklescan](https://github.com/mmaitre314/picklescan/blob/main/LICENSE) MIT, 427 stars; [ModelScan](https://github.com/protectai/modelscan/blob/main/LICENSE) Apache-2.0, 783 stars; [fickling](https://github.com/trailofbits/fickling/blob/master/LICENSE) LGPL-3.0, 671 stars (V). Only the first two are safe to study; none is linked.

**Implementation route**: write a bounded opcode walker in Swift from the [pickle module docs](https://docs.python.org/3/library/pickle.html) and [`pickletools`](https://docs.python.org/3/library/pickletools.html) (PSF-licensed documentation; the protocol is public). It reads opcodes and their argument lengths, keeps a memo of strings only (needed to resolve `STACK_GLOBAL`), builds no objects and imports nothing. Caps (I): 64 MiB per pickle, 2 million opcodes, depth and memo limits. The existing ZIP reader checks CRCs; this feature needs a tolerant mode that lists members without failing on CRC mismatch (a shared-contract question for the lead).

**Safety and privacy**: nothing is executed or deserialised; the scan reads only `.pkl` members, never tensor storage; strings are concealed like any other text.

**Risks and unknowns**: `.pkl` is shared between Python pickles and Apple's Pkl configuration language (macOS types it as Pkl source), so routing must sniff content (pickle protocol 2 and later starts with byte `0x80`, I) and must not take over genuine Pkl files; allow- and deny-lists need upkeep and will produce Uncommon noise on full-model pickles; a symbolic scan cannot prove "called versus merely imported"; wording must never imply a clean bill of health; legacy pre-1.6 PyTorch framing needs separate handling.

### 3. Agent session transcripts and chat exports (Lead with)

**What the preview shows**

- **Conversation mode**: user and assistant turns as a readable thread; thinking blocks collapsed; each tool call as a one-line chip ("Bash: npm test", "Edit: src/app.ts"); tool results collapsed with their size; sub-agent turns nested; unknown record kinds shown as one-line stubs with their `type`.
- **Summary**: working directory, git branch, tool and model versions, start time and duration, turns, token usage, tool-call histogram, files edited.
- **Actions table** (the audit view): commands executed, files written or edited, URLs fetched, MCP tools called. Findings: hidden Unicode inside tool results (a prompt-injection indicator); secret inventory (counts only, shared detector); risky commands (`rm -rf`, `curl | sh`, `sudo`, `git push --force`); writes outside the working directory; sync-folder warning.
- Format sniffing on the first records: Claude Code (`uuid`/`parentUuid`, `type` of `user`/`assistant`, `message.content` blocks of `text`, `thinking`, `tool_use`, `tool_result`); Codex rollout (`session_meta`, `response_item`, `event_msg`); OpenAI-style chat JSONL (`messages` with roles); ChatGPT `conversations.json` (list of conversations whose `mapping` is a tree of nodes walked from `current_node`); Claude export (`chat_messages` with sender and text) (S for the two export formats: [OpenAI forum](https://community.openai.com/t/decoding-exported-data-by-parsing-conversations-json-and-or-chat-html/403144) and third-party guides).
- For `conversations.json` the preview is a conversation index (titles, dates, message counts, models) read from the head of the file with an explicit "showing first N" notice; these exports can be very large (I).

**Verified locally (keys only)**: a 446-record Claude Code file contained 13 record types (`user`, `assistant`, `attachment`, `system`, `queue-operation`, `last-prompt`, `custom-title`, `agent-name`, `file-history-snapshot`, `file-history-delta`, `pr-link`, `atis-latch`, `cost-state`) and over 90 distinct top-level keys; a 403-record Codex file used `session_meta`, `event_msg`, `response_item`, `turn_context`, `token_usage_record` with a `payload` object (V). The third-party [format guide](https://claude-dev.tools/docs/jsonl-format) says the same: types evolve across versions (V as to what it says; it is not official documentation).

**Demand evidence** (stars, V, 2026-10-13): [opcode](https://github.com/winfunc/opcode) 22,412 (AGPL-3.0, prior art only), [claude-code-history-viewer](https://github.com/jhlee0409/claude-code-history-viewer) 2,246 (MIT; covers Claude Code, Codex CLI, Copilot, Gemini CLI, Cursor, OpenCode), [claude-code-transcripts](https://github.com/simonw/claude-code-transcripts) 1,700 (Apache-2.0), [claude-code-viewer](https://github.com/d-kimuson/claude-code-viewer) 1,296 (MIT). All are standalone apps or HTML generators; none is a Quick Look preview. Among Quick Look apps only QLook JSON claims anything close ("JSONL for AI-agent logs", VC, from the landscape document).

**Implementation route**: own mappers over the existing JSONL line reader; no dependency. Bounds (I): read the head and the tail of large sessions (files reach tens of MB), cap displayed turns at about 1,000 with a visible partial notice, cap tool-result excerpts. Registration: these are `.jsonl` files named by UUID or timestamp, so routing relies on content sniffing inside the existing JSONL type; `conversations.json` can also use the name hint. A Conversation mode is a new presentation, so it needs a small shared-contract addition and the registry pattern used for Diagram and Pages.

**Safety and privacy**: transcripts hold everything the agent saw, including file contents and credentials. Reuse the concealment pipeline and the "Copy concealed text" action so a transcript can be pasted into a bug report; no content thumbnails (the first prompt is private), a facts badge at most; sync-folder warning.

**Risks and unknowns**: schema churn (version labelled in the Summary and unknown kinds collapsed); privacy optics of showing conversation text in Finder previews; effort is L because the view is new; ChatGPT and Claude export schemas are documented only by third parties (S).

### 4. Mach-O binaries and libraries (Lead with, for Mac developers)

**What the preview shows**

- **Summary**: file type (executable, dylib, bundle, object, dSYM), architectures with slice offsets and sizes for universal files, platform, minimum OS and SDK (`LC_BUILD_VERSION`), UUID, install name and current/compatibility versions, build tool versions, Swift and Objective-C presence from section names, whether an `__info_plist` section is embedded.
- **Libraries table**: linked libraries with kind (normal, weak, re-export, upward), versions, and a path category (system, `@rpath`/`@loader_path`, absolute developer path); `LC_RPATH` entries.
- **Segments and sections table** with sizes; **Symbols** summary (counts, stripped or not, top exported symbols, bounded).
- **Signing**: from the `LC_CODE_SIGNATURE` blob, the embedded signature superblob, CodeDirectory (identifier, team ID, hash type, flags: ad-hoc `0x2`, hardened runtime `0x10000`, linker-signed), entitlements as the existing plist outline, signer certificate subjects. Values are "shown as stored, not verified", the same notice decision 017 uses.
- **Findings**: unsigned or ad-hoc; hardened runtime missing; risky entitlements (`get-task-allow`, `com.apple.security.cs.disable-library-validation`, `allow-dyld-environment-variables`, `allow-unsigned-executable-memory`); absolute build paths in install names or rpaths (they reveal usernames; concealed through the same pipeline); single-architecture Intel build; encrypted segments; very old minimum OS.
- **Thumbnail**: architecture and kind badge, as Library Inspector did with icons showing the architectures ([listing](https://apps.apple.com/us/app/library-inspector/id431808420), V).
- ELF and PE share the Summary, Libraries, Sections and Imports tables once the Binary presentation exists: ELF header, needed libraries, RPATH/RUNPATH, `PT_INTERP`, stripped flag; PE machine, subsystem, timestamp, imports, DLL characteristics (ASLR/DEP), signature presence. PE and ELF headers are specified by the System V gABI and Microsoft's PE documentation (not re-opened, I).

**Competitor coverage and how searched**: web search "Quick Look plugin Mach-O dylib" found Library Inspector only: version 2.1 dated July 10, 2016, macOS 10.9+, $3.99, "includes a Quick Look plugin", three reviews dated 2012, 2016 and 2023 (V). Legacy `.qlgenerator` plug-ins no longer load on macOS 15 ([Michael Tsai](https://mjtsai.com/blog/2024/11/05/sequoia-no-longer-supports-quicklook-generator-plug-ins), cited in the landscape). LookQuick's listing (v4.0, released about a week before this research) names `.exe`, `.dll`, `.reg`, Xcode projects, xcarchives and provisioning profiles, but not Mach-O, general binaries or crash logs (V); it also promises a hex/strings fallback and a "detector card" for unknown binaries (VC, from the UX research). `.app` signing details are claimed by Unfold and LookQuick (VC). The iTunes API sweep failed (see Method).

**Implementation route**

- Today the `.app` adapter reads the first 4 KiB of the executable for architectures (decision 017, V). Load commands follow the header (`sizeofcmds`), so a 1 to 2 MiB window covers them; the signature blob is at `dataoff`/`datasize` (cap 1 MiB); the symbol table is bounded (8 MiB string table, capped symbol count).
- Spec: [`loader.h`](https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h) and [`cs_blobs.h`](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/cs_blobs.h) (V: `CSMAGIC_EMBEDDED_SIGNATURE 0xfade0cc0`, `CSMAGIC_CODEDIRECTORY 0xfade0c02`, `CSMAGIC_EMBEDDED_ENTITLEMENTS 0xfade7171`, DER entitlements `0xfade7172`, `CS_RUNTIME 0x10000`, `LC_CODE_SIGNATURE 0x1d`, `LC_BUILD_VERSION 0x32`). Both headers carry Apple's open-source licence notice (APSL), so define our own constants from the layout and do not paste the files (I; confirm with whoever owns licence review).
- No Apple API parses Mach-O. [MachOKit](https://github.com/p-x9/MachOKit) is MIT, 281 stars, covers load commands, symbols, fat files and the dyld shared cache, and I could not confirm code-signature support (V); a small own parser is preferable because the repository needs a fraction of it and a dependency needs its own audit.
- Signing certificates: the existing `CMSDecoder` and `SecCertificate` paths (provisioning profiles, certificates). Whether `SecStaticCode` works inside the sandbox for a lone file is unverified; the plan avoids it by not verifying.
- Registration: `.dylib` and `.o` have system declarations that conform to data (V), `.a` and `.so` are dynamic. Bundles (`.framework`, `.xpc`, `.appex`, `.dSYM`) can follow the `.app` adapter's directory policy; `com.apple.xcode.dsym` and `com.apple.xcode.archive` exist as directory types here (V). Extension-free executables are not routable under the current `public.data` rule (AGENTS.md), so plain executables without a suffix are out of reach (V as a documented limit).

**Safety and privacy**: read-only, header windows only, nothing executed or loaded; no symbol or string contents beyond bounded names; absolute paths pass through concealment; thumbnails show facts only.

**Risks and unknowns**: executables without a suffix remain unreachable; the effort for symbols and sections is a separate M; competitor feature drift is fast (LookQuick ships roughly weekly, per its version notes).

### 5. Crash and diagnostic reports (Add)

**What the preview shows**

- **Summary** ("what happened" in one sentence): process, version and build, OS and device model, crash time and time since launch, exception type and codes, signal, termination namespace and indicator, translated (Rosetta) flag. Examples of plain-language mapping: null-page access for `EXC_BAD_ACCESS` at a tiny address, watchdog termination (`0x8badf00d`), `DYLD` library-missing termination (I).
- **Threads**: the crashed thread first with its backtrace, other threads collapsed, frames showing image, symbol where the report supplies one, and image offset otherwise; `lastExceptionBacktrace` when present; "Application Specific Information" text.
- **Images table**: binary images with UUIDs and architecture (the UUIDs are what you match against a `.dSYM`, which is a bridge to candidate 4).
- **Findings and actions**: unsymbolicated app frames ("addresses only; symbolicate with the dSYM matching UUID X"); user-path exposure; **Copy Redacted Summary** that removes usernames, `procPath`, `userID`, `bootSessionUUID` and `crashReporterKey` before pasting into an issue.

**Native today**: `.crash`, `.ips`, `.spin` and `.hang` resolve to `com.apple.crashreport`, `com.apple.ips`, `com.apple.spinreport` and `com.apple.hangreport`, all conforming to `public.text` (V). Finder therefore previews them as text (I; I did not render one). `.diag` is dynamic. Constraint 4 requires an evidenced gain: a digest and a redacted copy are one; routing priority against the system text previewer is untested.

**Local evidence of the format**: a real `.ips` from `~/Library/Logs/DiagnosticReports` is a JSON header line (`app_name`, `app_version`, `bug_type`, `build_version`, `incident_id`, `os_version`, `platform`, `slice_uuid`, `timestamp` and others) followed by a body JSON with `exception`, `termination`, `threads`, `usedImages`, `faultingThread`, `procName`, `procPath`, `codeSigningID`, `codeSigningTeamID` and more (V, keys only). Apple's [documentation of the JSON format](https://developer.apple.com/documentation/xcode/interpreting-the-json-format-of-a-crash-report) is JavaScript-rendered and returned only its title, so I could not read it; the local sample is the evidence.

**Demand**: the surrounding tooling shows the workflow need, not a count: [MacSymbolicator](https://github.com/GetToSet/MacSymbolicator) (GPL-2.0), [mac-ips2crash](https://pkg.go.dev/github.com/jpeizer/mac-ips2crash) and the Rust [symbolicate](https://www.lib.rs/crates/symbolicate) crate (S). I found no Quick Look app for these files.

**Route**: JSON and text parsers, no dependency; the legacy `.crash` text format needs a line parser. Bound at a few MiB of text. **Risks**: report layouts vary by `bug_type` and OS version; a digest must degrade to the raw outline; privacy copy must be exact.

### 6. Packet captures: pcap and pcapng (Add)

**What the preview shows**: capture duration and time range, packet and byte counts, link type, interface names and capture comments (pcapng `IDB`/`SHB` options), top conversations (address pairs, ports, bytes), protocol mix (Ethernet, IPv4/IPv6, TCP, UDP, ICMP, ARP; DNS and TLS by port and content), hostnames from pcapng name-resolution blocks, DNS queries and TLS SNI. Findings by count only, never values: cleartext HTTP Basic credentials, FTP/Telnet logins, SNMP community strings, plaintext SMTP/IMAP auth ("3 cleartext credentials seen"). Payloads are never shown, and thumbnails are facts-only.

**Native and competitors**: `.pcap`/`.pcapng` are dynamic types (V). Cocoa Packet Analyzer's listing mentions a Quick Look plug-in (S, from a search summary; it is an old app and I did not verify the plug-in works on macOS 15); TCP Viewer by Proxyman opens captures as a standalone app and does not mention Quick Look (S). None found for current macOS.

**Route**: own readers from the IETF [pcap](https://github.com/IETF-OPSAWG-WG/draft-ietf-opsawg-pcap) and pcapng drafts (V that the repository exists; spec text not re-read) and [libpcap](https://github.com/the-tcpdump-group/libpcap) (BSD) as reference. Magic numbers for classic pcap are `0xa1b2c3d4` and the nanosecond variant, in either byte order; pcapng starts with a Section Header Block `0x0A0D0D0A` (I, from the public specs). Scanning is sequential, so bound it (I): about 64 MiB or 200k packets, then show "first N packets" with a partial notice; header and DNS/TLS parsing limited to fixed offsets; no reassembly.

**Risks**: hostnames and addresses are personal data (a capture opened in Finder is still user-initiated, but screenshots may leak); protocol parsing is where effort grows (L); decrypted-capture (TLS key log) support is out of scope.

### 7. JavaScript source maps (Add)

**What the preview shows**: version, `file`, `sourceRoot`, counts of sources, names and mapping segments; index maps (`sections`); sources as a tree with sizes grouped into application code versus `node_modules`; selecting a source shows its embedded text as highlighted source (Files/Tree plus source text, existing presentations). **Findings**: "sourcesContent is present: anyone holding this file can read N original source files (X MB)"; secrets found inside embedded sources (shared inventory); absolute paths such as home directories in `sources` or `sourceRoot`; a map shipped next to a bundle.

**Why now**: a source map included in Claude Code's npm package 2.1.88 reportedly exposed its full source on March 31, 2026, and a similar incident was reported for February 2025 (S, secondary reporting only: [HackMag](https://hackmag.com/news/claude-code-leak)). I did not verify the incident details; the general failure mode (maps shipped to production with `sourcesContent`) is well known (I).

**Native and competitors**: `.map` is a dynamic type (V). JSON Loupe lists `.map` among its supported JSON types and offers head-only reads for huge files (VC). No Quick Look app was found that treats maps as source bundles.

**Route**: existing JSON adapter with size-aware budgets (maps reach tens of MB); VLQ `mappings` are not decoded, only counted; spec is ECMA-426 (S, I did not open it). No dependency. Effort S. **Risks**: the `.map` suffix is also used by other formats (linker maps), so detect by JSON shape.

### 8. Container image tarballs and Helm charts (Add)

**What the preview shows**: repository tags, OS and architecture, creation time, entrypoint, command, user (flag root), working directory, exposed ports, labels, environment variable names with values concealed by the shared filter, layer count and sizes, and the image history (`created_by` commands). Findings: runs as root; secret-like environment values; history lines that copy credentials (`COPY .env`, `ARG TOKEN`, `ADD id_rsa`); very large layers. A Layers table plus the existing Files listing.

**Why**: [GitGuardian](https://blog.gitguardian.com/fresh-from-the-docks-uncovering-100-000-valid-secrets-in-dockerhub/) reported over 100,000 valid secrets in a 15-million-image scan, and a 2023 RWTH Aachen study reported 52,107 valid private keys among 337,171 images (S, both). Prior art: [dive](https://github.com/wagoodman/dive) (MIT, 54,632 stars) for layers, a standalone CLI (V).

**Route**: `docker save`/`podman save` archives carry `manifest.json` and a config blob; OCI layouts carry `oci-layout`, `index.json` and `blobs/sha256/*` ([image-spec](https://github.com/opencontainers/image-spec/blob/main/image-layout.md), Apache-2.0). The TAR adapter already walks entries; the config JSON is a small member. Compressed tarballs need bounded decompression to reach the config (I). Helm `.tgz` charts: `Chart.yaml` and `values.yaml` summary after the same gzip-tar walk. Effort M. **Risks**: tar members are sequential so locating the config may need a full header scan; layers are never expanded.

### 9. WebAssembly modules (Add)

**What the preview shows**: module or component (preamble version and layer), section table with sizes, type/function/memory/table/global counts, **Imports** and **Exports** tables, start function, custom sections (`name`, `producers`, `target_features`, `component-type`), and the toolchain and language from `producers` (Rust, Emscripten, AssemblyScript and others). **Findings**: capability summary derived from imports (WASI preview 1 imports such as `fd_write`, `path_open`, `sock_*`, `proc_exit`; `env.*` host functions; a module that imports nothing is a pure function); debug info present; very large data segments.

**Native and competitors**: `.wasm` is dynamic; `.wat` source already highlights (V). No Quick Look app found (S). **Demand** is modest, not mass-market: [wabt](https://github.com/WebAssembly/wabt) 8,157 stars (Apache-2.0) and [wasm-tools](https://github.com/bytecodealliance/wasm-tools) 1,801 (Apache-2.0) (V). Browser viewers exist (S).

**Route**: own section reader from the [WebAssembly spec](https://webassembly.github.io/spec/core/binary/index.html) and [component model](https://github.com/WebAssembly/component-model) (both V that the repositories exist; spec text not re-read). Read the preamble then section headers, skipping code bodies; decode type, import and export sections only; LEB128 with strict bounds; no instruction decoding. Effort S to M. **Risks**: the component model is still moving; show "component" with a size and import summary only.

### 10. ONNX models (Add)

**What the preview shows**: IR version, opset imports (domain and version), producer and version, model version, doc string, `metadata_props`, graph name, **inputs and outputs with shapes and types**, node count, **operator histogram**, initializer count, parameter total (sum of initializer dimensions) and dtype breakdown, and a finding for **external data** ("weights live in `model.onnx.data`; that file is not read") and for custom operator domains that need an external library (I). Netron remains the graph viewer; this answers "what is this model" in two seconds.

**Demand**: [56,555 ONNX models on the Hub](https://huggingface.co/models?library=onnx) (V); [onnx](https://github.com/onnx/onnx) 21,584 stars, Apache-2.0 (V); Netron 33,568 stars (V). No Quick Look app found.

**Route**: the repository's bounded protobuf wire reader (built for AAB manifests) walks `ModelProto` and `GraphProto` by field number; raw weight bytes are skipped by length, never read; random access avoids reading multi-GB files. `onnx.proto` is Apache-2.0. The ONNX docs have an "External Data Security" page (V that it exists; text not read). Effort M. **Risks**: field numbers must be taken from `onnx.proto` (not re-opened); large graphs need node caps.

### 11. Keras v3 archives (Add, safety)

**What the preview shows**: a `.keras` file is a ZIP holding `config.json`, `metadata.json` and weights (I; Keras 3 saving format, not re-opened). The preview lists layers with class names and parameter counts when present, Keras and backend versions, and a finding for **`Lambda` layers** (they embed serialised Python) and for config entries that name modules or functions outside `keras.*`. Why: CVE-2025-1550 allowed code execution when loading a crafted `.keras` archive even with `safe_mode=True`, by editing `config.json` ([IBM bulletin](https://www.ibm.com/support/pages/node/7255407)), and a later bypass (GHSA-c9rc-mg46-23w3, August 2025) abused built-in Keras modules ([mirror](https://cvepremium.circl.lu/vuln/ghsa-c9rc-mg46-23w3)) (S, both). Keras is Apache-2.0, 64,372 stars (V). Route: existing ZIP reader plus JSON, effort S. Legacy `.h5` is out (see Ruled out).

### 12. TFLite and Core ML (Niche)

- **TFLite**: FlatBuffers with file identifier `TFL3` and a `Model` table (version, operator codes, subgraphs, buffers, metadata) (V: [LiteRT schema.fbs](https://github.com/google-ai-edge/LiteRT/blob/main/tflite/converter/schema/schema.fbs), Apache-2.0 header; the same file is mirrored in TensorFlow). Needs a small vtable reader (no schema compiler). Shows I/O tensors, op histogram, quantisation, metadata and description. Only [2,193 Hub models](https://huggingface.co/models?library=tflite) (V). Niche.
- **Core ML**: `.mlmodel` is protobuf (`Model.proto` in [coremltools](https://github.com/apple/coremltools), BSD-3-Clause, 5,436 stars, V); `.mlpackage` and `.mlmodelc` are directories whose manifests and `metadata.json` carry inputs, outputs, author, license and version (I). The types are declared (V) and Xcode shows its own model editor (I). The audience (Apple-platform ML developers) is the app's home audience, but the Hub lists only [2,586 Core ML models](https://huggingface.co/models?library=coreml) (V). Niche.

### 13. Keys and identities (Add)

**What the preview shows**: OpenSSH public keys and `authorized_keys` (key type, bit size, comment, SHA-256 fingerprint, options such as `command=`, `from=`, `no-pty`); `known_hosts` (count, hashed or plain hosts, key types); **private keys without ever showing material**: format (OpenSSH, PKCS#8, PEM RSA) and **whether encrypted** (the OpenSSH format records `ciphername` and `kdfname`, both `none` when unencrypted (V: [PROTOCOL.key](https://raw.githubusercontent.com/openssh/openssh-portable/master/PROTOCOL.key))); PGP armored or binary keys and keyrings (key IDs, user IDs, algorithms, creation and expiry, revocation) from OpenPGP packets; CSRs (subject, SANs, key and signature algorithms); CRLs (issuer, next update, revoked count); JWT (header and claims decoded as inert text, `alg`, expiry; `alg: none` flagged) and JWK/JWKS (key types, `kid`, private-parameter presence); Java keystores (JKS aliases, entry types, certificate subjects; private-key entries stay encrypted).

**Competitors**: Super Quick Look claims PEM/certificate/key files, `authorized_keys` and `known_hosts` (VC, landscape); nobody claims fingerprints, encryption status or PGP. The existing certificate type covers X.509 only (decision 017).

**Route**: a bounded DER walker (shared with candidate 4's CMS reading), OpenSSH wire format (public), OpenPGP packet headers per the IETF specification (RFC 4880/9580, not re-read), Security framework for X.509. No dependency. Effort M; PGP is the largest part. Passphrase-protected `.p12` and `.jks` reveal little without a password and are shown structurally only (I). **Risk**: partial overlap with Super Quick Look's coverage, so the differentiators must be fingerprints, encrypted-or-not and PGP.

### 14. Profiles and flame graphs (Add)

**What the preview shows**: a Top table (function, self, cumulative, percent) and a native **flame graph**, plus a summary (sample type and units, duration, sample count, binaries and build IDs from the profile). Formats: pprof (gzipped protobuf, `profile.proto`), V8 `.cpuprofile`, speedscope JSON, folded stacks. Thumbnails can draw the flame graph silhouette without any text, so they stay private. Findings: missing symbols (addresses only), home-directory paths (concealed).

**Demand**: [pprof](https://github.com/google/pprof) 9,299 stars (Apache-2.0), [speedscope](https://github.com/jlfwong/speedscope) 6,768 (MIT), [Perfetto](https://github.com/google/perfetto) 6,635 (Apache-2.0) (V). No Quick Look app found. Route: existing protobuf reader and gzip; JSON parsing for the others; a CoreGraphics drawing view (no Metal needed). Effort M for tables, L with the flame view. Heap snapshots and Perfetto binary traces are out.

### 15. Report digests: SARIF, SBOM, JUnit, coverage (Niche)

Digest views over JSON and XML that SpacePane already registers: **SARIF** (tool, runs, results by level and rule, top files), **CycloneDX and SPDX** (component counts by ecosystem, licence histogram with copyleft flagged, vulnerabilities array where present, components without hashes), **JUnit XML** (totals, slowest tests, failure messages concealed), **lcov and Cobertura** (per-file coverage table and total). Specs: [SARIF](https://github.com/oasis-tcs/sarif-spec), [CycloneDX](https://github.com/CycloneDX/specification) (Apache-2.0), [SPDX](https://github.com/spdx/spdx-spec) (V that the repositories exist). Demand is real but diffuse (CI and compliance work), I have no download counts, and these overlap the "dialect views" a features agent covers. Effort S each; ship as one batch if at all. Name the table "Results", not "Findings", to avoid colliding with the Safety Lens banner.

### 16. Binary JSON family and raw protobuf (Niche)

MessagePack, CBOR (including COSE/CWT hints), BSON (`mongodump` files are concatenated documents), Ion and UBJSON decoded into the existing outline/tree with the JSON text as an alternate view. `protoc --decode_raw` style decoding for `.pb`/`.binpb` using the existing wire reader. Parsers are small and bounded (depth, node and string caps; reject indefinite-length abuse), from public specs such as RFC 8949. Concealment applies to decoded strings. Risks: `.pb` is ambiguous (TensorFlow, ONNX, descriptor sets), so schema-less decoding is a heuristic and must say so; MessagePack has no magic number, so only its suffixes can route. No Quick Look app found. Effort S per format.

### 17. Fine-tuning and eval dataset check (Add, overlaps the features agent)

A Summary and findings layer over JSONL (the notebook-health-check pattern): detected shape (OpenAI chat `messages`, ShareGPT `conversations`, Alpaca instruction, preference pairs), row count, role-sequence errors, rows with no assistant message, empty content, duplicates, outlier lengths, estimated tokens (clearly labelled as an estimate: chars divided by about 4; exact counts need the model's tokenizer), hidden Unicode and secret counts. The OpenAI cookbook's data-preparation notebook does the same checks with `tiktoken` and calls its count "not exact" (S: [cookbook](https://developers.openai.com/cookbook/examples/chat_finetuning_data_prep)). Route: existing JSONL reader. Effort S. Registration needs no new suffix.

### 18. Terraform state (Niche)

A Resources table (type, name, provider, module, instance count), outputs with their sensitive flags, state version, Terraform version, serial and lineage, and a finding that the file stores plaintext values. HashiCorp states that state is a plaintext file and that marking values `sensitive` only redacts CLI output while the values stay in state and plan files (V: [Terraform docs](https://developer.hashicorp.com/terraform/language/state/sensitive-data)). Secret concealment already covers values; the new part is the inventory and the sync-folder warning. Binary `.tfplan` is a zip of internal files and is skipped; plan JSON from `terraform show -json` can share the parser. Effort S.

### 19. Xcode artifacts (Niche)

`.xcarchive` is a directory: `Info.plist` (name, scheme, creation date, application properties and signing identity), the embedded `.app` (reuses the app adapter) and `dSYMs/` UUIDs. LookQuick already claims xcarchives and Xcode projects (V), so the gain is small. `project.pbxproj` (conforms to text, V) could get a targets/build-phases/configurations outline. `.xcactivitylog` is a gzipped build log whose binary format [XCLogParser](https://github.com/MobileNativeFoundation/XCLogParser) (Apache-2.0, 1,852 stars, V) parses, so it is the reference for a clean-room reader; a digest of errors, warnings and slowest targets would help CI artifacts. `.xcresult` is ruled out below.

### 20 to 22. Smaller candidates (Niche)

- **`.class`, `.dex`, `.pyc`**: `.class` and `.pyc` have system declarations (V). Java class files expose major version (Java release), class and super names, interfaces, member counts and referenced classes; DEX headers expose string, type, method and class counts (the 64K method limit); `.pyc` headers give the Python version and source hash. JARs and APKs are already listed, but member files inside them are not previewed individually, which is the realistic use. Effort S each.
- **TFRecord, WebDataset shards, FAISS**: TFRecord is length-prefixed records of `tf.train.Example` protobufs, so the first records can be decoded into feature names and types without a schema. WebDataset shards are tar files grouped by key (the TAR reader exists). FAISS indexes begin with a four-character type, dimension and count. [FAISS](https://github.com/facebookresearch/faiss) is MIT, 41,143 stars (V). Rarely opened by hand; Niche.
- **Redis RDB and Git bundles**: RDB has a public format description; bundles hold a refs header before a packfile. Real but small audiences. Niche.

## Ruled out and why

- **Hex or strings dumps of unknown binaries**: rejected earlier (an ASCII column exposes secrets); unchanged.
- **Legacy Keras `.h5` and HDF5 in general**: parsing superblocks, object headers and attributes safely is L work for a shrinking format, and the HDF5 library is too large to link.
- **DuckDB (`.duckdb`)**: the engine is, to my knowledge, MIT-licensed (I), but embedding a database engine is far beyond "small", and I believe the catalog sits in an internal block serialisation (I). A type is declared on the dev Mac by a third-party app (V). Rule out.
- **LevelDB, RocksDB, LMDB, Realm, Berkeley DB, MS Access (`.mdb`/`.accdb`)**: directory-shaped or multi-file stores (sibling files are not readable), engine-sized parsers, or licences that rule them out (Berkeley DB is AGPL-licensed in recent versions and mdbtools is LGPL/GPL, both I). Rule out.
- **fickling, MachOKit-as-dependency, opcode (AGPL), MacSymbolicator (GPL-2.0), Wireshark (GPL)**: licence or dependency size; used only as reading material.
- **`.xcresult`**: a directory whose internal database is only supported through Apple's `xcresulttool`, which cannot run in the sandbox (I). **`Assets.car`**: undocumented, read by private CoreUI (I). **`.memgraph` and Instruments `.trace`**: private formats (V that they are declared as data/directory types, I for the rest). **Heap snapshots, OpenTelemetry exports, Perfetto binary traces**: very large, low per-file value.
- **TensorRT engines (`.engine`, `.plan`), OpenVINO (`.xml` + `.bin` pair)**: device-specific serialisation or a sibling-file pair. **LanceDB/Lance directories, HNSW and usearch indexes**: directories with versioned fragments, or no header magic.
- **ComfyUI workflow JSON, HF `config.json`/`tokenizer.json`, Ollama `Modelfile`, MCP configs, promptfoo/eval YAML, `.http` request files, Postman/Insomnia/Bruno collections, kubeconfig, docker-compose, OpenAPI, CI workflows**: JSON, YAML or text dialects. Per the brief these belong to the features agent; I noted overlaps only. (`kubeconfig` has no suffix and could not route anyway.) Ollama blobs are extension-free files named `sha256-...`, unreachable under the current routing rule.
- **Things you install or launch** (npm and PyPI packages, `.vsix`, `.mobileconfig`, Shortcuts, MCP bundles and skill archives): the trust agent's scope.
- **Cloud AI, executing models, loading checkpoints, unpickling**: excluded by constraints and decision 025.
- **Git packfiles and `.git/index`**: reachable only by browsing inside `.git`; negligible audience.

## Sources

Opened and verified (V):

- GGUF specification: https://github.com/ggml-org/ggml/blob/master/docs/gguf.md
- Hugging Face GGUF documentation: https://huggingface.co/docs/hub/gguf
- Hugging Face pickle scanning: https://huggingface.co/docs/hub/security-pickle
- safetensors repository: https://github.com/huggingface/safetensors and docs https://huggingface.co/docs/safetensors/index
- picklescan: https://github.com/mmaitre314/picklescan; fickling: https://github.com/trailofbits/fickling
- MachOKit: https://github.com/p-x9/MachOKit; Mach-O headers: https://github.com/apple-oss-distributions/xnu/blob/main/EXTERNAL_HEADERS/mach-o/loader.h and https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/cs_blobs.h
- Library Inspector listing: https://apps.apple.com/us/app/library-inspector/id431808420
- LookQuick listing: https://apps.apple.com/us/app/lookquick/id6759767692; Unfold changelog: https://unfold.tools/changelog
- TFLite schema: https://github.com/google-ai-edge/LiteRT/blob/main/tflite/converter/schema/schema.fbs
- OpenSSH key format: https://raw.githubusercontent.com/openssh/openssh-portable/master/PROTOCOL.key
- Terraform state and sensitive data: https://developer.hashicorp.com/terraform/language/state/sensitive-data
- Claude Code transcript format (third-party): https://claude-dev.tools/docs/jsonl-format
- Hub model counts: https://huggingface.co/models?library=gguf, https://huggingface.co/models?library=safetensors, https://huggingface.co/models?library=onnx, https://huggingface.co/models?library=pytorch, https://huggingface.co/models?library=mlx, https://huggingface.co/models?library=coreml, https://huggingface.co/models?library=tflite
- Repository stars and licences (GitHub API, 2026-10-13): ggml-org/llama.cpp, ggml-org/ggml, ollama/ollama, mudler/LocalAI, lutzroeder/netron, onnx/onnx, apple/coremltools, keras-team/keras, google/pprof, jlfwong/speedscope, google/perfetto, wagoodman/dive, WebAssembly/wabt, bytecodealliance/wasm-tools, facebookresearch/faiss, protectai/modelscan, gpustack/gguf-parser-go, kohya-ss/sd-scripts, MobileNativeFoundation/XCLogParser, winfunc/opcode, jhlee0409/claude-code-history-viewer, simonw/claude-code-transcripts, d-kimuson/claude-code-viewer, CycloneDX/specification, opencontainers/image-spec.
- Local checks on the development Mac (macOS 27.2): `UTType` declarations for ~120 suffixes; `.ips` key structure; Claude Code and Codex transcript key structure; `Packages/PreviewCore/Sources/PreviewContracts/Resources/FormatCatalog.json`.

Licence files (V, URLs from the GitHub licence API; none of these projects is linked or copied, they are specifications or reading material):

- MIT: [ggml](https://github.com/ggml-org/ggml/blob/master/LICENSE), [llama.cpp](https://github.com/ggml-org/llama.cpp/blob/master/LICENSE), [Ollama](https://github.com/ollama/ollama/blob/main/LICENSE), [huggingface.js](https://github.com/huggingface/huggingface.js/blob/main/LICENSE), [picklescan](https://github.com/mmaitre314/picklescan/blob/main/LICENSE), [MachOKit](https://github.com/p-x9/MachOKit/blob/main/LICENSE), [speedscope](https://github.com/jlfwong/speedscope/blob/main/LICENSE), [dive](https://github.com/wagoodman/dive/blob/main/LICENSE), [FAISS](https://github.com/facebookresearch/faiss/blob/main/LICENSE), [gguf-parser-go](https://github.com/gpustack/gguf-parser-go/blob/main/LICENSE), [claude-code-history-viewer](https://github.com/jhlee0409/claude-code-history-viewer/blob/main/LICENSE), [claude-code-viewer](https://github.com/d-kimuson/claude-code-viewer/blob/main/LICENSE).
- Apache-2.0: [safetensors](https://github.com/safetensors/safetensors/blob/main/LICENSE), [ModelScan](https://github.com/protectai/modelscan/blob/main/LICENSE), [ONNX](https://github.com/onnx/onnx/blob/main/LICENSE), [Keras](https://github.com/keras-team/keras/blob/master/LICENSE), [TensorFlow](https://github.com/tensorflow/tensorflow/blob/master/LICENSE), [LiteRT](https://github.com/google-ai-edge/LiteRT/blob/main/LICENSE), [pprof](https://github.com/google/pprof/blob/main/LICENSE), [Perfetto](https://github.com/google/perfetto/blob/main/LICENSE), [wabt](https://github.com/WebAssembly/wabt/blob/main/LICENSE), [wasm-tools](https://github.com/bytecodealliance/wasm-tools/blob/main/LICENSE-APACHE), [CycloneDX](https://github.com/CycloneDX/specification/blob/master/LICENSE), [OCI image-spec](https://github.com/opencontainers/image-spec/blob/main/LICENSE), [XCLogParser](https://github.com/MobileNativeFoundation/XCLogParser/blob/master/LICENSE), [sd-scripts](https://github.com/kohya-ss/sd-scripts/blob/main/LICENSE.md), [claude-code-transcripts](https://github.com/simonw/claude-code-transcripts/blob/main/LICENSE).
- BSD-3-Clause: [coremltools](https://github.com/apple/coremltools/blob/main/LICENSE.txt).
- Excluded by licence: [fickling](https://github.com/trailofbits/fickling/blob/master/LICENSE) LGPL-3.0; [opcode](https://github.com/winfunc/opcode) AGPL-3.0; ComfyUI GPL-3.0; MacSymbolicator GPL-2.0.
- Apple's `loader.h` and `cs_blobs.h` carry Apple's open-source (APSL) notice; the plan is to implement from the layout, not copy the files.

Search summaries only (S), not opened:

- nullifAI: https://thehackernews.com/2025/02/malicious-ml-models-found-on-hugging.html and https://threats.wiz.io/all-incidents/malicious-ai-models-bypass-picklescan-detection
- picklescan zero-days: https://jfrog.com/blog/unveiling-3-zero-day-vulnerabilities-in-picklescan/
- CVE-2025-32434: https://osv.dev/vulnerability/CVE-2025-32434
- Keras CVE-2025-1550: https://www.ibm.com/support/pages/node/7255407; bypass GHSA-c9rc-mg46-23w3: https://cvepremium.circl.lu/vuln/ghsa-c9rc-mg46-23w3
- Poisoned GGUF templates: https://www.pillar.security/blog/llm-backdoors-at-the-inference-level-the-threat-of-poisoned-templates and https://arxiv.org/pdf/2602.04653v3
- kohya metadata: https://civitai.com/articles/24796 and https://deepwiki.com/kohya-ss/sd-scripts/11.4-model-metadata-and-sai-modelspec
- Packet capture tools: https://apps.apple.com/us/app/cocoa-packet-analyzer/id418357707 and https://tcpviewer.proxyman.com/docs/features/open-capture-files; pcap specification repository https://github.com/IETF-OPSAWG-WG/draft-ietf-opsawg-pcap; libpcap https://github.com/the-tcpdump-group/libpcap
- Crash tooling: https://github.com/GetToSet/MacSymbolicator, https://pkg.go.dev/github.com/jpeizer/mac-ips2crash, https://www.lib.rs/crates/symbolicate; Apple (unreadable, JavaScript-rendered): https://developer.apple.com/documentation/xcode/interpreting-the-json-format-of-a-crash-report
- Source map leak reporting: https://hackmag.com/news/claude-code-leak
- Container image secrets: https://blog.gitguardian.com/fresh-from-the-docks-uncovering-100-000-valid-secrets-in-dockerhub/
- OpenAI fine-tuning data preparation: https://developers.openai.com/cookbook/examples/chat_finetuning_data_prep
- ChatGPT export format: https://community.openai.com/t/decoding-exported-data-by-parsing-conversations-json-and-or-chat-html/403144; Codex rollout format (blog): https://codex.danielvaughan.com/2026/03/30/codex-cli-session-analytics-jsonl-rollout
- WebAssembly: https://webassembly.github.io/spec/core/binary/index.html and https://github.com/WebAssembly/component-model; SARIF https://github.com/oasis-tcs/sarif-spec; SPDX https://github.com/spdx/spdx-spec
- Prior landscape and legacy plug-in context: https://mjtsai.com/blog/2024/11/05/sequoia-no-longer-supports-quicklook-generator-plug-ins (cited by the existing landscape document).
