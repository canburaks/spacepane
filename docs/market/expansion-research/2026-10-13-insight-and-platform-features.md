# Insight and platform features: what SpacePane could do that Quick Look apps do not

Researched 2026-10-13 (Europe/Istanbul). Angle: features rather than formats. Builds on [the unique-feature research](../2026-10-05-unique-feature-opportunities.md), [the competitor landscape](../2026-10-05-competitor-landscape.md), [decision 012](../../decisions/012-safety-findings.md), [decision 021](../../decisions/021-preview-interaction-and-live-reload.md) and [decision 022](../../decisions/022-content-thumbnails.md).

## 1. Method, evidence labels and limits

**Evidence labels used throughout**

| Tag | Meaning |
|---|---|
| **[V]** | Verified: I opened the source (Apple page, forum thread, vendor page, specification) in this session. |
| **[SDK]** | Read from the macOS 27.0 SDK in `/Applications/Xcode.app` on this Mac (headers and `.swiftinterface` files). This is Apple's own primary source for availability and extension-safety annotations. |
| **[PROBE]** | Measured by me on this Mac (macOS 27.2, build 26B5101f) with three small scratch Swift programs compiled in the session scratchpad, outside the repository. They query framework capabilities and write nothing. Results describe this machine, not every user's Mac. |
| **[VC]** | Vendor claim (a product page or earlier digest); not tested. |
| **[S]** | Secondary source: a search-result summary or news report I did not open. |
| **[I]** | My inference. |
| **[SPIKE]** | Needs an on-device experiment in a signed Finder-hosted build before anyone promises it. |

**Limits**

- The Mac App Store search API returned HTTP 403 and 429 for every query (eleven agents share one address), so I could not re-run the description scan that produced the 151-app corpus. Every "none found" below therefore rests on the earlier digest plus today's web searches. That is weak evidence. A follow-up should re-run the corpus with this keyword list: docker, compose, kubernetes, workflow, GitHub Actions, OpenAPI, swagger, launchd, LaunchAgent, entitlements, HAR, waterfall, JWT, timestamp, epoch, lightroom, anki, geopackage, mbtiles, chart, histogram, VoiceOver, accessib, translate, OCR, Live Text, Shortcuts, Intents, Spotlight.
- I could not open WWDC 2026 session pages. A search reported no Quick Look change in macOS 27 [S]. The SDK headers below are the stronger evidence.
- Newly discovered products worth adding to the landscape (not opened beyond search summaries [S]): **Looq** (Setapp; code, Markdown, CSV and SQLite as native tables), **Base 3.3** (a database editor whose Quick Look preview lists tables, views, triggers and indexes, and which documents a WAL limitation caused by the App Sandbox), **OmniPreview** (29 renderers incl. SQLite and GeoJSON), **CatalooK** (Quick Look for photo libraries incl. Lightroom) and **QLite** (open-source SQLite preview).
- Everything macOS 26 or 27 only needs an availability check, and [AGENTS.md](../../../AGENTS.md) forbids introducing one blind. Each such API is a "first use in its own small commit behind a narrow wrapper" item for a Mac session.

## 2. Key findings

1. **The cheapest distinctive work is dialect recognition, not new parsers.** JSON, YAML, TOML, XML, plist, SQLite and ZIP are already parsed, bounded and concealed. A conservative "Dialect Lens" on top (GitHub Actions, MCP/agent configs, launchd plists, docker-compose, Kubernetes, HAR, OpenAPI, package lockfiles, well-known SQLite schemas, extension bundles) reuses the facts header, findings banner, table, outline and diagram renderers. The real cost is not code but wording: every finding kind needs strings in 14 languages (decision 012), so the lens should use a handful of generic finding kinds with typed details.
2. **The strongest evidence of need sits where Safety Lens already is.** GitHub's own guidance says third-party actions should be pinned to a full commit SHA [V], and the `tj-actions/changed-files` compromise (CVE-2025-30066, 14-15 March 2025, more than 23,000 repositories, secrets printed to logs) is the proof [V]. MITRE lists LaunchAgent plists as a macOS persistence technique used by Cuckoo Stealer, GlassWorm and others [V]. Okta's 2023 incident turned on customer HAR files that carried session tokens [S]. Each maps to a finding no Quick Look app was found to show.
3. **Quick Look gave extensions nothing new.** The macOS 27.0 SDK headers for `QuickLookUI` and `QuickLookThumbnailing` expose the same surface as macOS 12: `QLPreviewingController`, `QLPreviewReply`, `QLFilePreviewRequest`, `QLThumbnailReply.extensionBadge` [SDK]. There is no new lever to exploit, and `CSImportExtension` still "doesn't provide functionality in macOS" according to Apple's current page [V]. Spotlight/Get Info metadata via Core Spotlight stays dead; only the legacy `.mdimporter` route is left.
4. **The Apple Intelligence frameworks are reachable, but "inside a Quick Look extension" is unproven for all of them.** None of Foundation Models, Translation, Vision, NaturalLanguage, Charts or TipKit carries an extension-unavailable annotation in the macOS 27 SDK [SDK] (by contrast, AppIntents marks `ForegroundContinuableIntent` as extension-unavailable). An Apple DTS engineer wrote in June 2026 that the system language model is not loaded into the extension's memory but that "some extensions do not allow XPC" and so cannot use it [V]. Whether the Quick Look preview extension is one of them is unknown. Every AI-flavoured idea below is **[SPIKE]**.
5. **Language coverage cuts the AI ideas down.** On this Mac the on-device model supports 24 locales including Turkish (`tr-Latn-TR`), but only 8 of SpacePane's 14 UI languages (English, Turkish, German, French, Simplified Chinese, Japanese, Portuguese, Spanish). It does not support Hindi, Kurmanji, Russian, Indonesian, Bengali or Hausa [PROBE]. The Translation framework lists 47 locales including `tr`, `hi`, `id`, `ru`, but not Bengali, Hausa or Kurmanji [PROBE]. NaturalLanguage named-entity tagging exists only for English and Turkish among 11 languages tested [PROBE]. A PII detector built on it would be nearly useless for the app's audience.
6. **The accessibility premise is partly false, but the opportunity is real.** At least one competitor, Folder Quick Look ($3.99), declares VoiceOver, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast and Reduced Motion in its App Store Accessibility section [V]. Apple says these labels are voluntary "for now" and will eventually be required [V]. Nobody found offers rotors, audio graphs or Braille support. SpacePane can make accessibility a verified, specific quality story, not a unique one.
7. **Shortcuts is the platform door competitors barely use.** `FileEntity` (macOS 15), `IntentFile` (macOS 13) and Spotlight actions on the Mac (WWDC25) let "Get Safety Findings" or "Copy Concealed Text" run from Spotlight, Shortcuts or a Finder Quick Action without any new window [SDK, V]. Only QLMarkdown claims Shortcuts actions [VC]. Sandbox file access for intent files needs `startAccessingSecurityScopedResource`, per community reports [V forum, 2021].
8. **Several tempting platform ideas should be dropped:** Finder Sync risk badges, Core Spotlight indexing, NaturalLanguage PII, a network "Private Cloud Compute" model (new in macOS 27, cannot work without the network entitlement and breaks the local-only promise), widgets, Focus filters and TipKit in the extension.

## 3. Ranked candidates

Effort: S = days, M = 1-2 weeks, L = several weeks (including strings, fixtures and tests). "QL ext?" means whether it is verified to work inside a sandboxed Quick Look extension. For the dialect features the answer is "yes by construction [I]": they are pure Swift over structures the pipeline already parsed, so no new API is involved.

| # | Feature | Who benefits | Competitor coverage | QL ext? (source) | Spike? | Reuses | Effort | Verdict |
|---|---|---|---|---|---|---|---|---|
| 1 | **CI workflow lens**: GitHub Actions job graph, triggers, permissions, secrets used, unpinned actions, script-injection patterns (then GitLab CI, CircleCI) | Developers, maintainers, reviewers of PRs | None found (searched "docker-compose / GitHub Actions / OpenAPI Quick Look"; weak) | Yes by construction [I] | No | YAML outline, diagram renderer, findings banner, facts header | M | **Lead with** |
| 2 | **Agent and MCP config lens**: `mcp.json`, `claude_desktop_config.json`, `.cursor/mcp.json`, `SKILL.md`, `AGENTS.md`, `.cursorrules`: what runs, with which env keys, which URLs | Anyone using AI coding agents (2025-26 threat) | None found | Yes by construction [I] | No | JSON/Markdown adapters, hidden-content scanner (agent-file context already exists), table | S-M | **Lead with** |
| 3 | **Plain-language launchd / Info.plist / entitlements**: "Runs X at login, every 300 s" plus persistence findings | Mac admins, security-minded users, developers | LookQuick shows app entitlements and usage strings [VC]; no launchd explanation found | Yes by construction [I] | No | Plist adapter, summary labels, findings | S-M | **Lead with** |
| 4 | **HAR lens**: waterfall, slowest and failed requests, third-party domains, token and cookie findings | Web developers, support engineers | HAR as JSON only (JSON Loupe [VC]); web analysers exist [S]; no Quick Look waterfall found | Yes (CoreGraphics; Charts has no extension-unavailable mark [SDK]) | No | JSON Records view, findings, plot view | M | **Lead with** |
| 5 | **JSON shape**: inferred schema, optionality, enums, number ranges, JSONL drift, **Copy as TypeScript / Swift / JSON Schema** | Developers, API and data people | None in Quick Look found; quicktype is a separate CLI/web tool [S] | Yes by construction [I] | No | JSON outline, Profile view, copy plumbing | M | **Lead with** |
| 6 | **docker-compose and Kubernetes**: service/network/volume graph, hardening findings, dangling references | DevOps, developers | None found | Yes by construction [I] | No | YAML outline, diagram renderer, findings | M | **Add** |
| 7 | **Well-known SQLite schemas**: "Lightroom catalogue, 12,400 photos", Core Data, browser history/cookies, Anki, MBTiles, GeoPackage; privacy findings | Photographers, analysts, forensics, curious users | Generic SQLite viewers only (Fast SQLite Viewer, Looq, Base [VC/S]); CatalooK previews photo libraries [S] | Yes by construction [I]; WAL files limited by sandbox (Base documents it [S]) | **Yes** (TCC-protected paths, WAL) | SQLite adapter, summary facts, diagram renderer (ER) | M, then S per dialect | **Add** |
| 8 | **Log timeline**: level histogram, gap detection, message-template clustering | Developers, ops | Colour-coded severity and stack traces (QuickestLook [VC]); no timeline found | Yes by construction [I] | No | Log adapter, plot view | M | **Add** |
| 9 | **Dependency and lockfile tables** with supply-chain findings (Cargo, Package.resolved, Podfile.lock, go.mod, pyproject, package-lock, Gemfile.lock, pom.xml) | Developers | Lock files shown as text (QuickestLook [VC]); no tables found | Yes by construction [I] | No | Table renderer, TOML/JSON/YAML/XML adapters | M (4 formats first) | **Add** |
| 10 | **OpenAPI / AsyncAPI / JSON Schema**: endpoint table, auth, unresolved `$ref` | API developers | None found | Yes by construction [I] | No | Table, outline, findings | S-M | **Add** |
| 11 | **Selection decoder** (inline bar): epoch seconds/ms, base64, URL parts, colour swatch, duration, QR code | Everyone who reads logs and configs | None found | `CIQRCodeGenerator`, `NSDataDetector` are old, plain frameworks [I] | Light | Go-to-Line inline-bar pattern | S-M | **Add** |
| 12 | **Charts from numeric columns** (CSV/Parquet/NumPy) with audio-graph descriptions | Analysts, VoiceOver users | Python Data Viewer charts `.npy` [VC]; none for CSV found | Charts has no extension mark [SDK]; hosting is a spike | **Yes** (memory, hosting) | Profile view, tables | M | **Add** |
| 13 | **App Intents / Shortcuts / Spotlight actions**: Get Safety Findings, Copy Concealed Text, Export Profile, Inspect File | Power users, automation, teams | QLMarkdown claims Shortcuts actions [VC] | Not an extension feature; runs in the companion [SDK, V] | **Yes** (file scope when run from Finder/Quick Action) | Whole preview pipeline | M | **Add** |
| 14 | **Accessibility as a verified quality story**: rotors for findings and headings, audio graphs, custom content, Braille, Nutrition Label | VoiceOver and Braille users; App Store positioning | Folder Quick Look declares VoiceOver etc. [V]; no rotors or audio graphs found | APIs are old AppKit/Accessibility [SDK]; Finder-hosted behaviour unverified | **Yes** (real VoiceOver in Finder) | Findings banner, tables, outline | M | **Lead with as quality, not as USP** |
| 15 | **Insight facts bundle**: certificate expiry countdown and weak-key findings, profile expiry and devices, EPUB reading time and accessibility metadata, Markdown outline health, diff statistics | Mixed | ProvisionQL covers profiles (legacy) [VC/S]; others none found | Yes by construction [I] | No | Facts header, findings | S each | **Add** |
| 16 | **Bundle manifest lens (ZIP dialects)**: `.mcpb/.dxt`, `.vsix`, `.crx/.xpi`, `.whl`, `.alfredworkflow`: permissions in plain English | Developers, security-minded users | CRX Source Viewer does this in a browser add-on [V]; no Quick Look found | Yes (one bounded manifest read) [I] | Light | ZIP reader with CRC-checked member reads (decision 025) | M | **Add** |
| 17 | **Share check + Copy Findings Report**: one verdict ("3 things to fix before sharing") and a ticket-ready Markdown report with no source values | Everyone who pastes files into tickets or AI chats | None found | Yes (copy to pasteboard) [I] | No | Findings, Copy Concealed Text | S | **Add** |
| 18 | **On-device "Explain this file"** (Foundation Models) | Curious users on Apple-Intelligence Macs | None in Quick Look found | **Unverified** (no extension mark [SDK]; DTS XPC caveat [V]) | **Yes** | Facts, findings | M | **Niche**, experimental |
| 19 | **Translate on device**: bilingual subtitle cues, EPUB paragraphs | Subtitle and ebook readers | None found | Headless init needs installed languages (macOS 26) [V]; extension use unverified | **Yes** | Subtitle and ebook adapters | M | **Niche** |
| 20 | **OCR for image-only pages** (Vision `RecognizeDocumentsRequest`, macOS 26) | Comic and scan readers | None found | Vision has no extension mark [SDK]; memory unverified | **Yes** | Pages view | M | **Niche** |
| 21 | Drag-out of extracted or derived content (entry, table as CSV, plot as PNG) | Archive and data users | Archive Quick Look extracts previews on demand [VC] | Unverified in the Quick Look host | **Yes** | Listings, tables | M | **Niche** |
| 22 | ZIP duplicate detection from central-directory CRC-32 and size | Anyone cleaning archives | None found | Yes by construction [I] | No | Archive analyser | S | **Niche** |
| 23 | Spotlight / Get Info metadata via `.mdimporter` | Power users | QLVideo ships a Spotlight component [VC] | Not an extension: separate plug-in | **Yes** | Facts | L | **Rule out for now** |
| 24 | Finder Sync risk badge on watched folders | Security-minded users | None found | Different extension type | Yes | n/a | L | **Rule out** |
| 25 | NaturalLanguage PII findings | n/a | None found | Works, but names only in English and Turkish [PROBE] | n/a | n/a | n/a | **Rule out** |

## 4. Dialect Lens: the shared design (applies to rows 1-10, 15, 16)

**What the user sees.** A one-line, quiet header from the existing facts mechanism: "Looks like a GitHub Actions workflow: 3 jobs, runs on push and pull request." The mode strip gains one derived mode (Graph, Endpoints, Services, Timeline or Dependencies, depending on the dialect) beside Source and Outline. Findings use the existing banner. Wording always says "looks like", never "is", and Source/Outline stay one click away.

**Conservative detection (proposal).**
1. Parse generically first. A lens never parses bytes itself and never runs when the generic parse failed or hit a budget.
2. Require **two signals** unless the structural signature is unambiguous: a name or path signal AND a structure signal. Examples: path contains `.github/workflows/` and the top level has `jobs` whose members hold `runs-on` or `uses`; file name `docker-compose.yml` or `compose.yaml` and a `services` mapping whose members hold `image` or `build`; `apiVersion` plus `kind` for Kubernetes; `openapi: 3.x` or `swagger: "2.0"` for OpenAPI (unambiguous alone); `Label` plus `ProgramArguments` or `Program` for launchd; a `log.entries` array with `request` and `timings` for HAR.
3. The extension receives the file URL, so path components such as `.github/workflows` are available without reading siblings (the sync-folder check already works this way, decision 012). **[I]; confirm the Finder-hosted URL is the real path and not a staging copy in a spike.**
4. Reads only the **already concealed** structure, exactly like the Profile view. Environment values in compose files and Secret data in Kubernetes stay concealed; the lens shows key names, counts and kinds.
5. Bounded by the existing node and line budgets; no extra file access; cancellation inherited.
6. **Catalog fit.** A lens is not a new file type. Add one switch to the File Types page ("Recognize file dialects", on by default) and, if wanted, per-lens rows later. A disabled host type must still disable its lenses (decision 002).
7. **String cost control.** Decision 012 requires a typed kind, wording and 14 translations per finding. Define about eight generic kinds with typed details, for example `config.unpinnedDependency`, `config.dangerousSetting(detail)`, `config.danglingReference`, `config.excessivePermission`, `config.remoteCodeAtStartup`, `config.credentialSource`. Dialect names ("GitHub Actions", "Kubernetes") are proper nouns and need little translation. This is what keeps ten lenses affordable.
8. **YAML gotcha [I]:** in YAML 1.1 the GitHub Actions key `on:` parses as the boolean `true`. Check how the repository's YAML reader treats it before the lens relies on it.

## 5. Candidate sections

### 5.1 CI workflow lens (row 1) — Lead with

- **User sees.** A header ("GitHub Actions workflow, 3 jobs, triggers: push, pull_request, runs on ubuntu-latest and macos-15"), a **Graph** mode with jobs as nodes and `needs:` edges, and findings such as "4 third-party actions are not pinned to a commit SHA", "`pull_request_target` checks out the pull request head", "workflow sets no `permissions`", "event data used inside `run:` (script injection pattern)" and "3 secrets are referenced (names listed, values never shown)".
- **Why distinctive.** Workflow linters (actionlint, zizmor) live in CI or the terminal. No Quick Look app was found that audits a workflow when you press Space in a PR checkout.
- **Evidence of need.** GitHub's secure-use page recommends full-SHA pinning for third-party actions and warns that a compromised action can read repository secrets and possibly use `GITHUB_TOKEN` to write to the repository [V: [docs.github.com](https://docs.github.com/en/actions/reference/security/secure-use)]. The same page notes a workflow lockfile as a stronger option for repositories that adopt it [V]; design the finding so it degrades if a lockfile is present. CVE-2025-30066: attackers repointed existing version tags of `tj-actions/changed-files` to a malicious commit that printed runner secrets into logs, affecting more than 23,000 repositories (CVSS 8.6) [V: [GHSA-mrrh-fwg8-r2c3](https://github.com/advisories/GHSA-mrrh-fwg8-r2c3)].
- **Route.** Walk the concealed YAML structure: `on`, `jobs.*.needs`, `jobs.*.uses`, `jobs.*.steps[].uses`, `.run`, `permissions`, `runs-on`, `strategy.matrix`. Build nodes and edges for the diagram renderer (it already lays out flowcharts, ER, state and sequence diagrams from a native model, see `PreviewRenderers/Diagrams/`). Classify `uses:` into local (`./`), Docker (`docker://`), first-party (`actions/`, `github/`), third-party pinned (40-hex SHA) and third-party unpinned (tag or branch). Later dialects: GitLab CI (`stages`, `needs`, `include`), CircleCI (`workflows`, `orbs`), Azure Pipelines.
- **Privacy/safety.** Names of secrets (`secrets.NPM_TOKEN`) are not secret values. Never expand expressions or fetch action metadata. All read-only.
- **Risks.** False positives (same-owner actions, internal actions); expression parsing needs care; the `on` key gotcha above. Effort M for Actions with the graph; each extra CI dialect S-M.

### 5.2 Agent and MCP config lens (row 2) — Lead with

- **User sees.** For an MCP config: a table of servers (name, how it starts, transport, environment variable names, remote URL) and findings such as "2 servers download and run the latest package at launch (`npx -y …@latest`)", "1 server pipes a download into a shell", "1 remote server uses http, not https". For `SKILL.md`, `AGENTS.md`, `CLAUDE.md` and `.cursorrules`: "this file tells an agent to run 7 commands and fetch 3 URLs" with an inventory, next to the existing hidden-Unicode banner.
- **Why distinctive.** It connects directly to the headline Safety Lens story (Rules File Backdoor, GlassWorm; see the 2026-10-05 digest). The 2026-10-05 digest found no Quick Look description that mentions AI-agent files in any role, and today's searches found none either [weak].
- **Evidence of need.** The 2025-26 incidents in the earlier digest; MITRE's page names GlassWorm and InvisibleFerret among macOS persistence-related families [V: [MITRE T1543.001](https://attack.mitre.org/techniques/T1543/001/)]. MCP bundles are ZIPs with a `manifest.json`, and the README I opened describes no signing [V: [modelcontextprotocol/mcpb](https://github.com/modelcontextprotocol/mcpb)].
- **Route.** JSON adapter for `mcpServers`; Markdown adapter for fenced and inline commands, URL tokens and front matter (`allowed-tools`). The existing agent-file context in the hidden-content scanner already knows these file names.
- **Privacy/safety.** Env **values** stay concealed; only names appear. Do not execute or resolve anything.
- **Risks.** Config schemas change quickly (`mcpServers` today); keep the detector structural and tolerant. Effort S-M.

### 5.3 Plain-language launchd, Info.plist and entitlements (row 3) — Lead with

- **User sees.** For a LaunchAgent or LaunchDaemon: "Runs `/Users/…/.cache/updater` at login, restarts if it exits, every 300 seconds. Per-user agent; no administrator needed." Findings: program in a hidden, temporary or user-writable folder; an interpreter with inline script (`osascript -e`, `sh -c`, `python -c`); a label that imitates `com.apple.*`. For an `Info.plist`: usage-description keys as "can ask for Camera, Contacts (with these reasons)", App Transport Security exceptions, URL schemes, background-only apps (`LSUIElement`). For entitlements: about 40 well-known keys explained in one sentence with a risk class.
- **Why distinctive.** LookQuick lists entitlements and privacy strings for app bundles [VC] and ProvisionQL does for profiles [VC/S], but a sentence-per-key explanation and launchd narration were not found.
- **Evidence of need.** MITRE: adversaries create or modify plists in LaunchAgents folders so payloads run at login; keys named are `Label`, `ProgramArguments`, `RunAtLoad`, `KeepAlive`; families include Cuckoo Stealer, Komplex and GlassWorm [V]. Plist is already a catalogued type, so the view exists; the explanation does not.
- **Route.** Plist adapter plus summary labels; a table from key to sentence template in the String Catalog.
- **Privacy/safety.** Path strings are shown as inert text. The sandboxed extension cannot reliably `stat` the target program, so do not claim "file missing" [I].
- **Risks.** About 40 sentences times 14 languages is real translation work; limit v1 to launchd plus the 15 most common entitlements. Effort S-M.

### 5.4 HAR lens (row 4) — Lead with

- **User sees.** A waterfall (one row per request; bars for blocked, DNS, connect, TLS, send, wait, receive), "slowest 5", "failed 3 (status 0 or at least 400)", bytes by type, third-party domain count, plus a privacy banner: "Contains 14 cookies and 3 Authorization headers; values concealed. Sanitize before sharing."
- **Why distinctive.** HAR is already in the catalog, and JSON Loupe opens HAR as JSON [VC]. Waterfall viewers exist only as web tools [S: [DebugBear](https://www.debugbear.com/har-file-analyzer)]. No Quick Look waterfall was found.
- **Evidence of need.** In October 2023 attackers used session tokens from customer-supplied HAR files to hijack sessions at Okta customers; Okta advised sanitizing credentials and cookies before sharing [S: [The Hacker News](https://thehackernews.com/2023/11/oktas-recent-customer-support-data.html), which I did not open]. This is a textbook Safety Lens finding: "this file would give a stranger your session."
- **Route.** The JSON Records presentation already exposes entries. Add a derived mode drawn with Core Graphics (no dependency; Swift Charts would also work, see 5.12). HAR 1.2 field names (`log.entries[].timings`, `startedDateTime`, `request.headers`, `response.status`) are from memory [I]; confirm against the spec in the fixtures.
- **Privacy/safety.** Count sensitive headers by **name** and conceal values with the existing policy; verify that `Authorization`, `Cookie`, `Set-Cookie` and bearer tokens in URLs are already caught, and add them if not.
- **Risks.** Entries can number tens of thousands; sample under the existing budget and say so. Effort M.

### 5.5 JSON shape and "Copy as types" (row 5) — Lead with

- **User sees.** A **Shape** mode: the inferred structure of a large JSON or JSONL file ("records: 41,203 objects; `id` integer, always present; `email` string, present in 38%; `status` one of 4 values; `created` ISO date strings"), with JSONL drift ("line 8,412: `user.id` is a string, elsewhere an integer"). Buttons: **Copy as TypeScript**, **Copy as Swift (Codable)**, **Copy as JSON Schema**.
- **Why distinctive.** quicktype and similar generators are CLI or web tools [S: [quicktype](https://github.com/MaxBrain/quicktype)]. No Quick Look app was found that infers a schema, which is exactly "understand, not just view". It also helps a 40 MB file you cannot read.
- **Route.** Walk the concealed outline once, bounded. Merge sibling objects into a union with optionality counts; classify strings (date, UUID, URL, number-like). Generated types contain **field names and types only, never values**. Reuses the Profile mechanics for JSONL and the existing copy plumbing.
- **Privacy/safety.** Field names can be sensitive in rare cases, so generate types from the concealed text only and mark concealed fields as `string`. Enumerated "one of 4 values" lists must not appear for concealed or sensitive-named fields.
- **Risks.** Heterogeneous data produces large unions; cap output. Naming collisions in generated Swift. Effort M.

### 5.6 docker-compose and Kubernetes (row 6) — Add

- **User sees.** A **Services** graph (services, networks, volumes, `depends_on`, published ports) and findings: "port 5432 is published on all interfaces", "service `db` mounts the Docker socket", "`privileged: true`", "image uses `latest`", "`depends_on` names a service that is not defined" (a single-file reference check). For Kubernetes: kinds and counts, containers and images, "Secret with 5 keys (values concealed)", `hostPath`, privileged containers, Service selectors that match no workload label in the same file.
- **Why it matters beyond looks.** Kubernetes `Secret` manifests hold base64 `data:` under arbitrary key names, which key-name heuristics can miss. A lens that knows `kind: Secret` can conceal every value under `data` and `stringData`. That is a concealment improvement as well as a feature [I; verify against `SecretFieldPolicy`].
- **Route.** YAML structure plus the diagram renderer; multi-document YAML needs a documents loop. Helm templates (`{{ }}`) are not YAML and must be detected and declined.
- **Risks.** Compose has several dialect versions; Kubernetes CRDs are open-ended, so only recognise core kinds. Effort M.

### 5.7 Well-known SQLite schemas (row 7) — Add, spike first

- **User sees.** "Lightroom Classic catalogue: 12,400 images, 38 collections" or "Firefox places database: 8,214 visited pages", with a privacy banner ("browsing history; values are shown only in the table view, subject to the existing concealment") and, where wanted, an ER diagram from declared foreign keys (the ER renderer exists).
- **Detection.** Two tiers. **Registered `application_id`** at header offset 68: SQLite's `magic.txt` lists GeoPackage (`GPKG`, `GP10`), Esri, **MBTiles (`MPBX`)**, Fossil, Bentley and TeXnicard [V: [magic.txt](https://www.sqlite.org/src/artifact?ci=trunk&filename=magic.txt)]. **Table signatures** for the rest, all [I] and version-dependent: Core Data (`Z_PRIMARYKEY`, `Z_METADATA`), Firefox (`moz_places`, `moz_cookies`), iOS backup `Manifest.db` (`Files`), Anki (`col`, `notes`, `cards`), Calibre (`books`, `authors`), Zotero (`items`, `itemTypes`), Django (`django_migrations`), Rails (`schema_migrations` plus `ar_internal_metadata`). Never infer from a file name.
- **Why distinctive.** SQLite viewers show tables. Nobody found names the application and counts its objects. CatalooK previews photo libraries but does not describe a catalogue [S].
- **Privacy/safety.** Facts are counts, not content. For history, cookies and chat databases, add a finding that the file holds personal data, and rely on existing table concealment. Chat and Photos databases are normally protected by TCC; Quick Look may never receive them, or only copies [SPIKE].
- **Risks.** Table signatures drift across app versions; label "looks like". WAL-mode databases hit the sandbox limit that Base documents [S: [Base docs](https://menial.co.uk/base/docs/macos-integration/quick-look/)], and the repository already has a no-source-write rule. Effort M for the framework plus S per dialect.

### 5.8 Log timeline (row 8) — Add

- **User sees.** A **Timeline** mode: a histogram of events per time bucket coloured by level, gaps ("no entries for 4 h 12 min at 03:10"), and the top message templates with counts ("`Connection to <ip> timed out`: 1,204").
- **Distinctiveness.** QuickestLook colours severity and stack traces [VC]; no timeline or clustering found.
- **Route.** In the log adapter: timestamp recognition (ISO 8601, syslog, Apache/nginx combined, unified-log text), level extraction, then template clustering by replacing numbers, hex, UUIDs and IPs with placeholders and counting identical templates (a simplified Drain-style approach [I]). Everything derives from concealed text, so clusters cannot leak a value the Source mode hides.
- **Risks.** Time-zone ambiguity (show as parsed, say so); huge logs (head-sample plus an honest notice). Effort M.

### 5.9 Dependency tables and supply-chain findings (row 9) — Add

- **User sees.** A Dependencies table (name, requested, resolved, source) for `Cargo.lock`, `Package.resolved`, `Podfile.lock`, `package-lock.json`, `Gemfile.lock`, `go.mod`, `pyproject.toml`; findings: "3 dependencies come from a git URL or http, not a registry", "wildcard or `latest` requirements", "install-time scripts declared (`postinstall`)".
- **Evidence of need.** The supply-chain stories the repository already cites (GlassWorm, Shai-Hulud-style worms; MITRE's family list includes both GlassWorm and Mini Shai-Hulud [V]).
- **Competition.** Lock files are listed as highlighted text (QuickestLook [VC]); `package.json` overviews exist (QuickLook Pro [VC]). No tables found.
- **Route.** Four formats first (Package.resolved JSON, Cargo.lock TOML, package-lock JSON, Podfile.lock YAML) using the Table renderer. Effort M.

### 5.10 OpenAPI, AsyncAPI, JSON Schema (row 10) — Add

- **User sees.** An Endpoints table (method, path, summary, auth, deprecated) with tag grouping and "unresolved `$ref`: 2". JSON Schema: a properties outline with required markers.
- **Distinctiveness.** Swagger UIs are web tools; nothing found in Quick Look. Detection is unambiguous (`openapi: 3.x`, `swagger: "2.0"`, `asyncapi:`). Reuses table and outline renderers. Effort S-M.

### 5.11 Selection decoder (row 11) — Add

- **User sees.** Select a number, string or colour in any text mode and an inline bar (like Go to Line, decision 021, no window or popover panel) shows: epoch seconds, milliseconds or microseconds as local time, UTC and "3 days ago"; base64 decoded (as text only if printable); URL parts; a colour literal as a swatch; a duration; and a **QR code** drawn from the selected string.
- **Why distinctive.** None found. It turns the preview into a reading tool.
- **Conflict to resolve.** JWT claim decoding collides with concealment: JWT-shaped tokens are credentials and the shared filter hides them, so the decoder never sees the token. Decode only `exp`/`iat` of unconcealed tokens, or leave JWT out. I recommend leaving it out of v1.
- **Route.** Operates on the **displayed (concealed)** selection only. `NSDataDetector` (dates, links, phone numbers) and Core Image's QR generator are old frameworks [I, not opened]. Effort S-M.

### 5.12 Charts from numeric columns with audio graphs (row 12) — Add

- **User sees.** In the Profile view of a CSV, Parquet or NumPy file, a chart button per numeric or date column: histogram, line over time, top-N bars. VoiceOver users hear an audio graph.
- **API facts.** `Charts.framework` exists in the macOS 27 SDK with no extension-unavailable annotation [SDK]. `AXChartDescriptor` (the audio-graph description) has been available since macOS 12 [SDK: `Accessibility.framework/Headers/AXAudiograph.h`]. The SwiftUI modifier that attaches a descriptor to a chart is documented by Apple but I did not open it [I].
- **Risks.** Hosting Swift Charts in an extension's AppKit view and its memory cost are a **[SPIKE]**; the Profile sparkline already proves a lighter path (a drawn 8-bin chart). Start with Core Graphics bars plus `AXChartDescriptor`, then decide on Charts. Effort M.

### 5.13 App Intents, Shortcuts and Spotlight actions (row 13) — Add

- **User sees.** Actions in Shortcuts, Spotlight and (via "Use as Quick Action") Finder's Quick Actions menu: **Get Safety Findings** (returns text), **Copy Concealed Text**, **Export Profile**, **Inspect File** (facts). No window opens, so the single-window rule (AGENTS.md) holds.
- **API facts.** `FileEntity` and `FileEntityIdentifier` are available from macOS 15; `IntentFile` from macOS 13 [SDK]. Apple's WWDC25 session says Spotlight on the Mac can now invoke an app's actions from anywhere, provided the intent has a parameter summary that includes all required parameters [V: [WWDC25 244](https://developer.apple.com/videos/play/wwdc2025/244/)]. Intents run in the companion app's process and sandbox, which already holds `files.user-selected.read-write` (`Configuration/app.entitlements`). Files handed to an intent are security-scoped: community reports say to call `startAccessingSecurityScopedResource()` [V forum, 2021, no Apple reply: [thread 692630](https://developer.apple.com/forums/thread/692630)]. The same thread reports `INFile` arriving nil when a shortcut ran as a Finder Quick Action; that was macOS 12 and is unresolved there, so it is a **[SPIKE]** on current macOS.
- **Why distinctive.** QLMarkdown claims Shortcuts actions [VC], but nobody exposes safety findings for automation, e.g. "scan every file in Downloads for hidden Unicode".
- **Rejected-list check.** Decision 025 rejected a Finder action that bypasses provider choice and standalone viewer windows. This is neither: it returns data, not a preview.
- **Risks.** String and localization load (intent titles, parameter summaries, dialogs in 14 languages); intent output may contain sensitive text, so return only concealed text and findings. Effort M.

### 5.14 Accessibility as verified quality (row 14) — Lead with as quality, not USP

- **Reality check.** Folder Quick Look declares VoiceOver, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast and Reduced Motion in its App Store Accessibility section [V: [listing](https://apps.apple.com/app/id6753110395)]. Apple's labels cover, on the Mac, VoiceOver, Voice Control, Dark Interface, Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion, Captions and Audio Descriptions (not Larger Text); they are voluntary now and will become required later [V: [Apple](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/)]. No competitor was found describing rotors, audio graphs or Braille.
- **What would be substantive.**
  - **Rotors** for findings, headings, outline rows and table columns: `accessibilityCustomRotors` (macOS 10.13) [SDK: `NSAccessibilityProtocols.h`].
  - **Audio graphs** for every drawn chart: `AXChartDescriptor` (macOS 12) [SDK].
  - **More Content** (`AXCustomContent`, macOS 11; block form macOS 14) to put detail such as a finding's lines behind VoiceOver's "more content" gesture [SDK].
  - **Spoken math** with `AXMathExpression` (macOS 15.2) for LaTeX and Markdown math [SDK].
  - **Braille**: `AXBrailleMap` (macOS 12.1) for 2D shapes such as a mesh silhouette or a plot, and `AXBrailleTranslator` (macOS 26) [SDK]. Niche; do last.
  - Reduced motion and contrast variants already exist as theme controls.
- **Risk.** AGENTS.md records that VoiceOver in a Finder-hosted preview is unverified. Do not claim anything on the App Store label until a person has driven the Finder-hosted preview with VoiceOver on, and a Braille display for any Braille claim. Effort M for rotors plus audio graphs.

### 5.15 Insight facts bundle (row 15) — Add, S each

- **Certificates.** Expiry countdown ("expires in 12 days", "expired 3 days ago"), chain length, self-signed, RSA below 2048 bits, SHA-1 signature, missing subject alternative name. Security framework data is already parsed for the certificate preview [I].
- **Provisioning profiles.** Expiry, device count and list, team, entitlements (ProvisionQL does expiry and devices [VC/S], so this is parity plus findings).
- **EPUB.** Reading-time estimate and the accessibility metadata in the package document (for example `schema:accessibilityFeature`). The metadata names are from memory [I]; the European Accessibility Act relevance is also from memory and **could not be verified** this session.
- **Markdown.** Reading time and outline health: skipped heading levels, duplicate headings, empty links, images without alt text.
- **Diff.** Statistics and a file map: files, additions, deletions, and which touch lockfiles, CI, `.env` or binaries.

### 5.16 Bundle manifest lens for ZIP dialects (row 16) — Add

- **Dialects not yet recognised** (other agents evaluate the individual formats): `.mcpb`/`.dxt` (MCP bundles) [V], `.vsix` (VS Code extension; `extension.vsixmanifest`) [S], `.crx`/`.xpi` (browser extensions; `manifest.json`), `.whl` (Python wheel; `METADATA`, `entry_points.txt`), `.nupkg` (`.nuspec`), `.appx`/`.msix` (`AppxManifest.xml`), `.alfredworkflow` (contains scripts), `.apkg`/`.colpkg` (Anki), `.sketch`, `.sb3` (Scratch), `.xmind`, `.xpi` and `.ora`/`.kra` image projects. Several of these contain manifests that grant code execution or broad permissions.
- **User sees.** "What this bundle can do": for an extension, the permissions in plain English with a risk class; for a wheel, console scripts and dependencies; for `.mcpb`, the launch command, tools and `user_config` fields; for `.alfredworkflow`, "contains 4 scripts".
- **Evidence.** CRX Source Viewer (a Firefox add-on) already explains extension permissions in plain English with risk levels, which proves the need but not a Finder surface [V: [listing](https://addons.mozilla.org/firefox/addon/crx-source-viewer/)]. No Quick Look equivalent was found.
- **Route.** ZIP central directory plus one bounded, CRC-checked member read (decision 025's `ZIPArchiveReader`). Effort M for the framework; S per dialect.

### 5.17 Share check and Copy Findings Report (row 17) — Add

- **User sees.** A header chip: "3 things to fix before sharing this file" with a checklist built from all existing findings (hidden characters, concealed secrets, risky archive entries, sync-folder location, HAR tokens). A **Copy Findings Report** action puts a Markdown report (finding kinds, counts, line numbers, no source values) on the pasteboard, for a ticket or a chat.
- **Why distinctive.** Competitors mask or list; none was found that turns findings into a share verdict or a paste-ready report. It makes Safety Lens legible to people who never read a banner.
- **Route.** Pure aggregation over typed findings (decision 012 says findings carry no source values); localized report template. Effort S.
- **Companion idea.** "Why was this hidden?": click a concealed token to see which rule class matched (kind, not value). Builds trust and gives users a way to report false positives. Effort S.

### 5.18 On-device "Explain this file" (row 18) — Niche, experimental

- **What was established.**
  - The framework is `FoundationModels`, macOS 26.0+; macOS 27 adds a model-capabilities API (vision, guided generation, reasoning, tool calling) and model variants (`core3`, `coreAdvanced3`) [SDK]. On this Mac the model is available, with a context size of 8,192 tokens; the SDK code returns 4,096 on releases before 27 [PROBE, SDK]. Apple staff previously said about 4,000 tokens [S].
  - Supported locales on this Mac: da, de, en (AU, GB, IN, US), es (419, ES, US), fr (CA, FR), it, ja, ko, nb, nl, pt (BR, PT), sv, **tr**, vi, zh (Hans-CN, Hant-HK, Hant-TW) [PROBE]. SpacePane UI languages **not** supported: Hindi, Kurmanji, Russian, Indonesian, Bengali, Hausa.
  - `SystemLanguageModel.Availability` can be unavailable for `deviceNotEligible`, `appleIntelligenceNotEnabled` or `modelNotReady`; guardrails are `default` or `permissiveContentTransformations`; error cases include guardrail violation, refusal, unsupported language, context exceeded, rate limited and timeout [SDK].
  - macOS 27 adds `PrivateCloudComputeLanguageModel`, a **network** model with quotas [SDK]. It cannot work without a network entitlement and would contradict "no network", so never use it.
  - **Extensions.** DTS (June 2026): the system model is not loaded into the app or extension memory, so it does not count against the extension's limit, but extensions that disallow XPC cannot use it [V: [forum 833575](https://developer.apple.com/forums/thread/833575)]. A 2025 thread reports rate limiting when a process runs in the background on battery and recommends `respond` over streaming there [V: [forum 789788](https://developer.apple.com/forums/thread/789788)].
- **User sees (if the spike passes).** An explicit "Explain" button (never automatic) producing three labelled lines: kind of file, what it appears to do, anything unusual, marked "AI-generated, may be wrong".
- **Prompt-injection exposure.** A previewed file is untrusted text, and a model reading it can be steered by it (the hidden-content threat model, inverted). Mitigations [I]: no tools; constrained structured output with guided generation; file text passed as data under fixed instructions; show hidden-content and secret findings first; send only the concealed text; a size cap; never act on the output.
- **Privacy.** On-device only, but disclose it in the privacy copy. It is a new data flow to a system service, and text leaves the extension process for the model service.
- **Verdict.** Niche. The audience is Apple-Intelligence Macs, the output language covers 8 of 14 UI languages, and the fit with a "your file is untrusted" brand is awkward. Run the spike (does `SystemLanguageModel.default` respond from a Quick Look preview process at all?) only if the owner wants it. Effort M after the spike.

### 5.19 Translate on device (row 19) — Niche

- **What was established.** `TranslationSession` is macOS 15+. For contexts without UI, `init(installedSource:target:)` (macOS 26.0 per the SDK interface) throws if the languages are not installed; downloads are requested through the SwiftUI `translationTask` path, so the companion must host the download prompt [V: [Apple doc](https://developer.apple.com/documentation/translation/translationsession); SDK]. Translation runs on device; Apple may collect usage metrics, including bundle ID and the language pair but not the content [V], which needs a line in the privacy copy.
- **Languages on this Mac.** 47 supported locales including `tr`, `hi`, `id`, `ru`, `de`, `fr`, `ja`, `zh`, `pt`, `es`; **not** Bengali, Hausa or Kurmanji; all tested pairs reported "installed" [PROBE].
- **Feature.** The system already offers Translate from the selection context menu [I]. What it does not do is a **bilingual view with structure preserved**: subtitle cues translated cue by cue (batch `translations(from:)` returns responses mapped by `clientIdentifier`) with a "Copy translated SRT" action, or EPUB paragraphs side by side. Effort M, and only after a spike that a Quick Look preview process can create the session.

### 5.20 Vision OCR (row 20) — Niche

- `RecognizeDocumentsRequest` (document structure: paragraphs, tables, lists) and `RecognizeTextRequest` exist; the former is macOS 26.0 [SDK]. Neither carries an extension-unavailable mark [SDK].
- **Feature.** Comic pages (CBZ) and image-only EPUB pages become text on request ("Copy text on this page"), with all processing on device. macOS already offers Live Text for images in Quick Look, so this adds value only inside SpacePane's own Pages view. On demand only, never during load; memory is a **[SPIKE]**. Effort M.

### 5.21 Drag-out and 5.22 ZIP duplicates — Niche

- **Drag-out.** A file promise lets the user drag a derived item (table as CSV, plot as PNG, an EPUB cover) to Finder. It is unverified inside the Quick Look host; Apple warns view-based previews to avoid large-area gestures [V: `QLPreviewingController.h` comments, SDK]. Extracting **archive entries** through a drag reopens the zip-bomb and unsafe-name risks and must reuse the archive risk analyser to refuse flagged entries. The extension has no write entitlement (`preview.entitlements`), so only promised files are possible. **[SPIKE]**, Effort M.
- **ZIP duplicates.** The central directory stores CRC-32 and sizes, so duplicate members (same size and CRC) can be reported without decompressing anything. S. Folder treemaps already exist in competitors (SpacePeek, FolderPlus [VC]), so skip them.

## 6. Platform capability matrix (what Apple actually permits)

All SDK facts come from the macOS 27.0 SDK on this Mac. "Entitlement" lists what I found documented; none of these frameworks listed an entitlement in the pages I opened.

| Capability | Availability | Inside the Quick Look preview extension? | Entitlements | What it would be |
|---|---|---|---|---|
| Foundation Models | macOS 26.0; 27 adds vision, reasoning, tools, network PCC model [SDK] | Unverified. No extension mark [SDK]; DTS says memory is not charged, XPC caveat [V] | None found | "Explain" (5.18) |
| Translation | macOS 15; headless `init(installedSource:)` macOS 26 [V, SDK] | Unverified | None found | Bilingual cues (5.19) |
| Vision text and documents | `RecognizeTextRequest`; `RecognizeDocumentsRequest` macOS 26 [SDK] | Unverified; memory | None found | OCR (5.20) |
| NaturalLanguage | Old framework; entity tagging only en and tr in my test [PROBE] | Works as a library [I] | None | Rule out for PII |
| `AVSpeechSynthesizer` | Old framework (not opened) | Audio playback already exists for MIDI, unverified in Finder | None | Read aloud: low value, since system Spoken Content exists [I]; skip |
| Writing Tools, Look Up, Data Detectors | `NSTextView.writingToolsBehavior` macOS 15 [SDK]; others old | Free on selectable `NSTextView`; behaviour on read-only text is a [SPIKE] | None | Verify rather than build |
| Live Text on images | Quick Look provides it on images (Apple user guide figures, per [the earlier UX digest](../ux-research/2026-10-06-system-and-benchmarks.md); not re-opened) | Host feature, not ours | None | None |
| Swift Charts | Charts framework present [SDK] | Unverified hosting | None | Charts (5.12) |
| TipKit | Present [SDK] | No sensible surface in a Quick Look view | None | Companion onboarding only; out of scope |
| App Intents, App Shortcuts, Spotlight actions | `FileEntity` macOS 15, `IntentFile` macOS 13 [SDK]; Spotlight actions [V] | Not applicable: companion process | Existing user-selected read-write | Shortcuts (5.13) |
| Core Spotlight import extension | macOS 12 header, but "doesn't provide functionality in macOS" [SDK, V: [Apple](https://developer.apple.com/documentation/corespotlight/csimportextension)] | Not functional | n/a | Dead |
| `.mdimporter` plug-in | Legacy; Apple points to the archived guide [V] | Separate plug-in, not the QL extension | Not researched | Rule out for now |
| Finder Sync | `FinderSync.framework` present [SDK]; Sequoia removed its Settings UI, a DTS engineer said a later beta restored it [S: [forum 756711](https://developer.apple.com/forums/thread/756711)] | Different extension | App Group, sandbox | Rule out |
| Services menu, Share extension, Finder Quick Actions | Quick Actions come from Shortcuts [S: [MacRumors](https://www.macrumors.com/how-to/use-finder-quick-actions)] | Not applicable | Not researched | Covered by Shortcuts |
| Quick Look API | Unchanged since macOS 12: `QLPreviewReply`, `providePreview(for:)`, `preparePreviewOfFile(at:)`, `preparePreviewOfSearchableItem`, `QLThumbnailReply.extensionBadge` [SDK] | Yes (what we use) | App Group | No new levers |
| Thumbnails with badges | `extensionBadge` since macOS 12 [SDK] (already used, `ThumbnailBadge`) | Yes | None | A risk badge would need parsing in the thumbnail path, which decision 022 forbids |
| Drag-out | AppKit file promises | Unverified in host | No write entitlement | 5.21 |
| Print / PDF export | `QLPreviewReply(forPDFWithPageSize:…)` exists for data-based previews [SDK] | The app is view-based; a Save panel needs the companion | Companion has user-selected read-write | Copy report instead (5.17) |
| AppleScript, CLI | Not researched | Not applicable | n/a | App Intents replace it |
| Widgets, Control Center, Focus filters | Not researched | Not applicable | n/a | Rule out (no per-file surface) |
| Accessibility APIs | Rotors macOS 10.13; `AXChartDescriptor` macOS 12; `AXBrailleMap` 12.1; `AXMathExpression` 15.2; `AXBrailleTranslator` 26 [SDK] | AppKit accessibility works in extensions [I]; verify in Finder | None | 5.14 |

## 7. Wholly new concepts (none found in any Quick Look app)

1. **Share check** (5.17): one verdict and a checklist from all findings.
2. **Copy Findings Report** (5.17): ticket-ready, value-free.
3. **"Why was this hidden?"** (5.17): the rule class behind a concealed token.
4. **Reference integrity inside one file**: dangling `depends_on`, `needs`, `$ref`, selectors and anchors, reported as one generic finding kind across all lenses (5.1, 5.6, 5.10).
5. **Agent-file command inventory** (5.2): "this file tells an agent to run 7 commands".
6. **Schema drift in JSONL and CSV** (5.5): "line 8,412 changed type", "column 7 is a date in 98% of rows and text in the rest".
7. **Text hygiene facts for any text file**: mixed line endings, byte-order mark, NUL bytes, tabs mixed with spaces, trailing whitespace counts, inconsistent CSV delimiters. A tiny addition to the facts header [I].
8. **Time-to-expiry strip** across certificates, profiles and any expiring-field file (5.15): one visual language for "this stops working in 12 days".
9. **Safety Lens in Shortcuts** (5.13): scan a folder from an automation and get findings back as data.

## 8. Ruled out, and why

| Idea | Reason |
|---|---|
| Finder Sync risk badge | Different extension type; had Settings visibility problems on Sequoia [S]; would scan every file in watched folders; heavy and fragile. |
| Core Spotlight import extension | Apple: "don't provide functionality in macOS" [V]. |
| `.mdimporter` metadata | Legacy plug-in route, not researched for Mac App Store acceptance; indexing table names and counts of every file adds privacy exposure. Revisit only with a spike. Prior proposal: still unproven. |
| NaturalLanguage PII findings | Name tagging only in English and Turkish [PROBE]; patterns (`SecretFieldPolicy`) already cover the high-value cases. |
| Private Cloud Compute model | Network; contradicts the product promise. |
| JWT payload decoding | Collides with concealment (5.11). |
| Risk badge on thumbnails | Needs file parsing in the thumbnail path and a durable cache (decision 022). |
| Read aloud | System Spoken Content already exists; low value. |
| Widgets, Control Center, Focus filters, TipKit in the extension | No per-file surface; companion window rules. |
| Writing Tools rewriting | Read-only previews; system behaviour only. |
| Folder treemaps | Already offered in part by SpacePeek and FolderPlus [VC]. |

## 9. Sources

**Apple (opened, [V])**
- Core Spotlight: [CSImportExtension](https://developer.apple.com/documentation/corespotlight/csimportextension)
- Translation: [TranslationSession](https://developer.apple.com/documentation/translation/translationsession)
- WWDC25: [Get to know App Intents (244)](https://developer.apple.com/videos/play/wwdc2025/244/)
- App Store Connect: [Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels/)
- Developer Forums: [Using FoundationModels framework in Extensions (833575)](https://developer.apple.com/forums/thread/833575), [Foundation Models rate limit in an app extension (789788)](https://developer.apple.com/forums/thread/789788), [Shortcuts action with File parameter and sandbox (692630)](https://developer.apple.com/forums/thread/692630)
- Forum seen only in search summaries [S]: [FinderSync extensions gone in macOS settings (756711)](https://developer.apple.com/forums/thread/756711), [CSImportExtension failing to index (713953)](https://developer.apple.com/forums/thread/713953)
- macOS 27.0 SDK at `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/` [SDK]: `FoundationModels.framework` (swiftinterface), `Translation.framework`, `Vision.framework`, `AppIntents.framework`, `CoreSpotlight.framework/Headers/CSImportExtension.h`, `QuickLookUI.framework/Headers/*`, `QuickLookThumbnailing.framework/Headers/*`, `FinderSync.framework/Headers/FinderSync.h`, `Accessibility.framework/Headers/{AXAudiograph,AXBrailleMap,AXBrailleTranslator,AXMathExpression,AXCustomContent}.h`, `AppKit.framework/Headers/{NSAccessibilityProtocols,NSTextView}.h`

**Security and specifications (opened, [V])**
- GitHub: [Secure use reference for Actions](https://docs.github.com/en/actions/reference/security/secure-use), [GHSA-mrrh-fwg8-r2c3 / CVE-2025-30066](https://github.com/advisories/GHSA-mrrh-fwg8-r2c3)
- MITRE: [T1543.001 Launch Agent](https://attack.mitre.org/techniques/T1543/001/)
- SQLite: [application_id registry (magic.txt)](https://www.sqlite.org/src/artifact?ci=trunk&filename=magic.txt)
- MCP: [MCP Bundles (mcpb)](https://github.com/modelcontextprotocol/mcpb)

**Products and secondary sources**
- Opened [V]: [Folder Quick Look (App Store listing)](https://apps.apple.com/app/id6753110395), [QLVideo README](https://github.com/Marginal/QLVideo)
- Not opened, from search summaries [S]: [The Hacker News on the Okta HAR incident](https://thehackernews.com/2023/11/oktas-recent-customer-support-data.html), [Base Quick Look documentation](https://menial.co.uk/base/docs/macos-integration/quick-look/), [Looq on Setapp](https://setapp.com/apps/looq), [CatalooK](https://www.waerfa.com/catalook), [CRX Source Viewer](https://addons.mozilla.org/firefox/addon/crx-source-viewer/) (summary only), [ProvisionQL](https://github.com/cocoaplayground/ProvisionQL), [DebugBear HAR analyzer](https://www.debugbear.com/har-file-analyzer), [quicktype](https://github.com/MaxBrain/quicktype), [MacRumors on Finder Quick Actions](https://www.macrumors.com/how-to/use-finder-quick-actions)

**Repository documents read**
- [AGENTS.md](../../../AGENTS.md), [2026-10-05 unique feature opportunities](../2026-10-05-unique-feature-opportunities.md), [2026-10-05 competitor landscape](../2026-10-05-competitor-landscape.md), [decision 012](../../decisions/012-safety-findings.md), [decision 021](../../decisions/021-preview-interaction-and-live-reload.md), [decision 022](../../decisions/022-content-thumbnails.md), [decision 025](../../decisions/025-competitor-parity-program.md), [2026-10-06 system and benchmarks](../ux-research/2026-10-06-system-and-benchmarks.md), `Configuration/preview.entitlements`, `Configuration/app.entitlements`, `Packages/PreviewCore/Sources/PreviewRenderers/Diagrams/`.

**Not verified this session (do not rely on)**
- WWDC 2026 session content (App Intents sessions 344/345, Core Spotlight, Visual Intelligence); the claim that macOS 27 adds Shortcuts automation triggers.
- European Accessibility Act relevance to EPUB metadata; HAR 1.2 field names; table signatures of Lightroom, Anki, Calibre, Zotero and browser databases; `NSDataDetector` and Core Image QR availability; Mac App Store acceptance of an `.mdimporter`; the `.vsix`, `.whl` and `.crx` manifest layouts (from memory except where marked).
