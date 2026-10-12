# Unique feature opportunities

Researched 2026-10-05 (Europe/Istanbul). Builds on [the competitor landscape](2026-10-05-competitor-landscape.md).

**What "unique" means here:**
- Not found in any of the **151 Mac App Store app descriptions that mention Quick Look**, checked by pattern matching and then reading each hit in context.
- Not found on the competitors' websites or GitHub repositories reviewed for the landscape.
- Not found by targeted web searches.

That is strong evidence, not proof, and a competitor could copy any idea quickly. All ideas below are proposals. None is a plan commitment until it goes through PLAN.md and a decision record.

## The opportunity in one sentence

Every competitor competes on **how many formats they can show**. None tells you **what is risky or surprising inside a file**.

SpacePane already treats every file as untrusted and conceals secrets. Extending that into a **Safety Lens** gives it a position no one holds: *the Quick Look that tells you what's really in a file.* It fits the brand ("Private by design"), the architecture (the privacy pipeline already scans text) and this year's threats.

## Ranked opportunities

Effort: S ≈ days, M ≈ 1–2 weeks, L ≈ several weeks, per format, including localization and fixtures.

| # | Feature | Unique? | Evidence of need | Feasibility | Effort |
|---|---|---|---|---|---|
| 1 | Hidden-content detector | ✓ none found | Strong, 2025–2026 attacks | High | M |
| 2 | Archive risk report | ✓ none found | Strong, macOS malware via archives and DMGs | High | S–M |
| 3 | Secret inventory, sync-folder warning, redacted copy | ✓ beyond masking | Medium | High | S |
| 4 | Notebook health check | ✓ none found | Strong (1.4M-notebook study) | High | S |
| 5 | CSV/TSV/JSONL data profile | ✓ among Quick Look apps | Medium | High | M |
| 6 | CAD dimensions, volume, structure | ✓ among Quick Look apps | Medium | Medium | M–L |
| 7 | Download provenance strip for documents and data | ✓ for these types | Medium | Spike needed | S |
| 8 | Privacy-safe structure thumbnails | ✓ concept | Medium | High | M |
| 9 | MIDI piano roll and structure | ✓ none found | Low–medium | High | M |
| 10 | Subtitle quality check | ✓ none found | Niche | High | S |
| 11 | Spotlight and Get Info metadata | Partly (QLVideo does video) | Medium | Uncertain | M–L |
| 12 | On-device "Explain this file" | ✓ in Quick Look | Unproven | Unknown | M, experimental |

### 1. Hidden-content detector
- **What it does:** a banner warns, for example, "This file contains 214 invisible characters that can hide instructions or code". A toggle shows each one as a visible marker. Unicode *Tag* characters are decoded into readable text, so the hidden message itself can be read, safely, as inert text.
- **What it detects:**
  - Bidirectional controls (Trojan Source).
  - Zero-width characters.
  - Unicode Tags (U+E0000–E007F, "ASCII smuggling").
  - Variation selectors and private-use characters (GlassWorm).
  - Mixed-script look-alike letters in identifiers.
  - Text that disappears when rendered, such as HTML comments in Markdown.
- **Where it applies:** every text format, with special attention to AI-agent files (`AGENTS.md`, `CLAUDE.md`, `.cursorrules`, `SKILL.md`, `mcp.json`), configs and source code.
- **Why now:**
  - The Pillar Security "Rules File Backdoor" (March 2025) hid instructions for Cursor and Copilot in rules files with invisible Unicode ([The Hacker News](https://thehackernews.com/2025/03/new-rules-file-backdoor-attack-lets.html), [Pillar](https://pillar.security/blog/new-vulnerability-in-github-copilot-and-cursor-how-hackers-can-weaponize-code-agents)).
  - GlassWorm (October 2025 to March 2026) hid code in invisible variation selectors across about 433 VS Code, OpenVSX, GitHub and npm components ([Koi](https://koi.ai/blog/glassworm-first-self-propagating-worm-using-invisible-code-hits-openvsx-marketplace), [CSA](https://labs.cloudsecurityalliance.org/research/csa-research-note-glassworm-supply-chain/)).
  - A 2026 phishing wave abused Unicode Tags, rising from about 21,000 to 1.3 million emails a day ([reporting summary](https://www.gblock.app/articles/ascii-smuggling-invisible-unicode-phishing-2026)).
  - Trojan Source is CVE-2021-42574.
- **Uniqueness:** zero hits in the 151 Quick Look descriptions. The only "invisible characters" mention is an editor showing tabs and newlines. A web search found detectors only as ESLint and VS Code tools, never in Quick Look.
- **Fit:** a bounded text scan in the existing pipeline. Needs a decision on how markers interact with copy and logical line numbers, keeping copy exact as AGENTS requires.

### 2. Archive risk report
- **What it does:** turns a ZIP/TAR/GZIP/XIP listing into a plain-language verdict, for example "3 things to check before extracting".
- **What it flags:**
  - Path traversal (`../`) and absolute paths ("zip slip").
  - Symlinks that point outside the archive.
  - Decompression-bomb ratios and total unpacked size.
  - Encrypted entries.
  - Apps, executables, scripts (`.command`, `.sh`, `.pkg`) and nested archives.
  - Double extensions (`invoice.pdf.app`) and right-to-left-override tricks in entry names.
  - Hidden dotfiles, case-colliding names and `__MACOSX` clutter.
- **Why:**
  - Infostealers made up more than 65% of newly reported macOS malware in 2025 and often arrive in disk images and archives (see the 2026 notnullOSX, CrashStealer and AMOS reports in the [threat summary](https://threatcluster.io/cluster/weaponized-dmg-files-target-macos-users-with-infostealer-mal-9236409a)).
  - Right-to-left-override filename spoofing has real macOS history: Janicab's `RecentNews.fdp.app` displayed as a PDF ([Macworld](https://www.macworld.com/article/221449/new-digitally-signed-mac-malware-confuses-users-with-right-to-left-file-name-tricks.html)).
- **Uniqueness:** zero hits. BetterZip's Quick Look shows only a Ratio column ([BetterZip docs](https://macitbetter.com/library/betterzip/docs/quick-look-extension/)), and every competitor only lists entries.
- **Fit:** works on the central directory and headers SpacePane already reads; no extraction. Reading the first bytes of an entry to catch a document that is really an app is a later, bounded step.

### 3. Secret inventory, sync-folder warning and redacted copy
- **What it does:**
  - Goes beyond masking with an inventory, for example "4 credentials: AWS access key (line 7), GitHub token (line 12), private key block, password field". It shows types, counts and lines, never values.
  - Warns when such a file is inside iCloud Drive or `~/Library/CloudStorage` (Dropbox, Google Drive, OneDrive).
  - Offers an explicit **Copy redacted** action, so a config or log can be pasted into a ticket or AI chat safely.
- **Uniqueness:** QuickLook Pro and QuickestLook mask secrets, but no description mentions an inventory, location warnings or redacted copy (zero hits).
- **Fit:** `DefaultPrivacyFilter` already classifies the patterns. The location check is a URL test with no extra file access.

### 4. Notebook health check
- **What it does:** a banner for `.ipynb` files, for example:
  - "Cells ran out of order: 5 → 2 → 9."
  - "3 code cells never ran."
  - "2 cells saved an error."
  - Kernel and language, plus a "may not reproduce" hint.
- **Why:** a study of 1.4 million GitHub notebooks found that only about 20% re-ran without exceptions and only about 4% reproduced their results. Hidden state and out-of-order execution were leading causes ([MSR 2019](https://2019.msrconf.org/details/msr-2019-papers/36/A-Large-scale-Study-about-Quality-and-Reproducibility-of-Jupyter-Notebooks)).
- **Uniqueness:** zero hits. Unfold, QuickestLook, Python Data Viewer and Quick Data Insights render notebooks but never assess them.
- **Fit:** uses `execution_count` and outputs the adapter already parses; nothing runs.

### 5. Data profile for CSV/TSV/JSONL
- **What it does:** a Profile view with, for each column:
  - Inferred type, missing values (%), distinct count, min/max/mean and top values.
  - A small histogram.
  - Quality flags: mixed types, ragged rows, duplicate headers, inconsistent dates, and leading zeros a spreadsheet would drop.
- **Uniqueness:** Peek: Markdown JSON Mermaid shows column types and a schema sidebar. Stats File Viewer Pro computes statistics, but for SAS/Stata/SPSS files in its own app. No Quick Look app offers distributions, missing values or quality flags. Profilers exist only as web or CLI tools ([csvsight](https://pypi.org/project/csvsight), [in-browser profiler](https://hidekazu-konishi.com/tools/csv_preview_statistics_tool.html)).
- **Fit:** profile a bounded sample under the existing budgets. Sensitive columns stay concealed, and their top values and statistics must be suppressed too.

### 6. CAD dimensions, volume and structure
- **What it does:**
  - Overall size with units (bounding box), volume, surface area and solid/face counts.
  - Header facts: schema AP203/214/242, originating system, author.
  - Later: a part/assembly tree and click-to-measure in the 3D view.
- **Uniqueness:** full Mac CAD viewers measure (IGES & STEP Viewer, STEP File Viewer, the open-source MacStep), but none does it in Quick Look. The Quick Look 3D apps found (Universal 3D Previewer, StepPreview, MakersPreview, Eyemesh and others) show models only. Combined with IGES support, which no one else offers, this makes a strong engineering story.
- **Fit:** the OCCT helper already imports geometry. Bounding box and mass properties are cheap. Assembly names need the XCAF reader, so that part is larger. All of it stays in the disposable byte-only helper.

### 7. Download provenance strip
- **What it does:** shows, for example, "Downloaded from github.com with Safari · 3 days ago · quarantined", read from the `com.apple.quarantine` and `kMDItemWhereFroms` attributes, for archives, data and documents.
- **Uniqueness:** App Trust Preview shows download history, but only for apps, installers, disk images and scripts.
- **Risks:** download URLs can contain tokens, so show the host by default and strip query strings. The strip should be opt-in, since URLs can reveal browsing during screen sharing. Reading these attributes inside the sandboxed extension needs a spike.

### 8. Privacy-safe structure thumbnails
- **What it does:** Finder icons that show a file's **shape, never its contents**:
  - CSV: column grid plus a row-count bar.
  - JSON: a depth silhouette.
  - Notebook: a strip of code, Markdown and output cells.
  - Archive: entry count plus a risk badge.
  - MIDI: track lanes.
- **Why:** competitors either draw content, which can leak data into Finder caches, or a generic icon. AGENTS already forbids sensitive content in thumbnails, so this is the compliant way to close the thumbnail gap.

### 9. MIDI piano roll and structure
A piano roll with a playhead synced to playback, plus a track list with General MIDI instrument names, tempo and time-signature map, key, note range, duration, and lyrics and markers (`.kar`). Today the most any competitor offers is QuickLook Pro's transport and scrubber.

### 10. Subtitle quality check
Flags overlapping cues, zero or negative durations, reading speed above a characters-per-second limit, long lines, tiny gaps, and encoding problems. Unfold highlights timing; no one checks quality.

### 11. Spotlight and Get Info metadata
Indexes only safe, structural facts: table names, row and column counts, notebook kernel, MIDI duration and tempo, STEP size and units, archive entry counts and risk flags. QLVideo does this for video. Apple's modern `CSImportExtension` is reported as non-functional on macOS ([Apple forums](https://developer.apple.com/forums/thread/713953)), although QLVideo ships a Spotlight extension, so this needs a spike before any promise.

### 12. On-device "Explain this file" (experimental)
A short local summary from Apple's Foundation Models framework, on macOS 26 Macs with Apple Intelligence only, gated by OS version. No competitor offers on-device AI in Quick Look. hYYa ink sends text to cloud keys, and PlantUML QuickLook sends files to a server: the anti-pattern SpacePane avoids. Open questions:
- Whether the framework can run inside a Quick Look extension at all.
- Whether summaries can be prompt-injected. Mitigate by showing feature 1's warning first and never letting the model take actions.

## Ideas rejected because they already exist or break principles

- **Already offered by competitors:**
  - Provider-conflict badge and scanner (LookQuick).
  - JSON mind map (Peeka).
  - App bundle inspection (Unfold, LookQuick, App Trust Preview, Peeka).
  - Mermaid and math (Unfold, Peek, QLMarkdown).
  - Live reload (Unfold).
  - In-preview search and jump to line (Peek).
  - Pretty JSON text (QLook JSON).

  These are worth matching later, not worth leading with.
- **Rejected on principle:**
  - Cloud AI or remote rendering, which breaks "local only".
  - Running notebook cells, which AGENTS forbids.
  - Comparing two selected files, because Quick Look gives an extension one file at a time.

## Recommendation

1. **Ship the Safety Lens first** as one coherent story. Start with the quick, verifiable wins:
   - Notebook health (S).
   - Archive risk report (S–M).
   - Secret inventory with the sync-folder warning and redacted copy (S).

   Then build the hidden-content detector (M), the headline feature with the strongest 2025–2026 evidence.
2. **Then "understand, not just view":** the data profile (M) and CAD dimensions (M), each a sharp story for one audience (analysts, engineers).
3. **Run spikes before promising:** download provenance in the sandboxed extension, Spotlight indexing, and Foundation Models inside an extension.

**Architecture note:** features 1–4 and 9–10 share one new presentation capability: typed **findings** (kind, severity, location, count) produced by adapters or the privacy policy and rendered by a common banner with localized wording. This is the "small shared-contract change with a documented reason" that AGENTS allows. Record it in a decision before implementation, with fixtures for each finding and translations in all 14 languages.

**Marketing note:** say "no other Quick Look app we found…" rather than "the only", and recheck before launch. The category changes monthly.
