# 019 — Code, configuration and text breadth

Date: 2026-10-05. Status: implemented locally for the competitor parity program ([025](025-competitor-parity-program.md)); signed Finder routing, thumbnails, VoiceOver and native-speaker review are not verified. Evidence: [the validation record](../validation/code-2026-10-05.md). Competitor claims (Unfold, Super Quick Look, QuickestLook, Simple Quick Look, PeekCode, JSON Loupe) are vendor claims from [the market analysis](../market/2026-10-05-competitor-landscape.md); everything below is original work over public specifications.

## What changed

| Area | Result |
|---|---|
| Language-aware highlighting | 84 languages through a data-driven profile table; `SourceCodeAdapter` names the language from the file name, `SourceSyntaxTokens` applies the profile |
| Source Code breadth | 181 suffixes and 71 well-known file names (up from 28 and 24) |
| New formats | `config.ini`, `text.log`, `data.jsonc`, `text.substation-alpha`, `text.ttml`, `text.sbv`, `text.lrc`, `text.microdvd` |
| Existing formats | lock files, `.entitlements`, `.xcstrings`, `.webmanifest`, `.code-workspace`, `tsconfig.json` map to existing or new formats |
| Minified JSON | an over-long JSON line is pretty-printed instead of failing, with a "Formatted for display" notice |
| Partial previews | a line-oriented text file over the input budget shows its leading complete lines and reports the full size |
| Stretch | `.xcstrings` shows a keys-by-languages table next to the JSON modes |

Hex dumps remain out of scope.

## Language profiles

`SourceLanguageID` statics live in `CodeFormatIDs.swift` with `SourceLanguageID.all`. A language has two independent halves that only share that identifier:

- **Detection** (`PreviewFormats/Code/SourceLanguageDetector`): exact lowercased file name, then name prefix (`Dockerfile.dev`), then final suffix; for extension-free scripts the interpreter on the `#!` line (`env`, `-S` and version digits are skipped). It uses `PreviewNameHint`, never reads sibling files and never decides which format handles a file.
- **Decoration** (`PreviewRenderers/Code`): `SourceLanguageProfile` is plain data (line, block and nested comments, string forms with escapes, doubled quotes, raw `r#"…"#` and `#"…"#`, triple-quoted and template strings, character literals that leave Rust lifetimes alone, numeric forms, keyword/type/literal sets, case sensitivity, preprocessor lines, decorators, key styles for `name =`, `NAME=` and `name:`). `ProfiledSourceTokenizer` is the only code that interprets it. Families live in `SourceLanguageProfiles+*.swift`; markup languages (HTML, Vue, Svelte, Astro, template engines) use a tag/attribute pass instead.

The tokenizer is lexical, not a grammar: no heredocs, regex literals or string interpolation. It makes one pass over UTF-16 units; each construct advances exactly once, an unterminated string ends at its line, an unterminated block comment at the text end, so work is linear (a 190 KB source decorates in about a quarter of a second in a debug test, and 100,000 unclosed `/*` produce one token). Ranges are exact UTF-16 offsets and never overlap. With no language, or a language without a profile, the previous generic rules run unchanged.

**Budget choice.** The profile tokenizer, like the new line tokenizers, decorates the first `maximumUTF16Units` units (256 Ki) and returns at most `maximumTokens` tokens, instead of returning nothing when a cap is exceeded as the generic path does. A large log or source file is therefore colored from its start. The generic and JSON paths keep their all-or-nothing behavior so existing expectations stay valid.

## Source Code breadth and routing

181 suffixes cover the languages named in the brief (Objective-C/C++, C#, F#, VB, Dart, Lua, Perl, R, Julia, Haskell, OCaml, Elixir, Erlang, Clojure, Scala, Groovy/Gradle, Zig, Nim, Crystal, D, Fortran, Pascal, Ada, assembly, VHDL, Verilog/SystemVerilog, Solidity, GraphQL, Protocol Buffers, Thrift, HCL/Terraform, Nix, Starlark/Bazel, CMake, Meson, Vue/Svelte/Astro, SCSS/Sass/Less, PowerShell, batch, fish, Nushell, AppleScript, Prisma, PlantUML source, shaders, WebAssembly text) plus names such as `Containerfile`, `Jenkinsfile`, `Vagrantfile`, `Procfile`, `Justfile`, `Fastfile`, `Cartfile`, `BUILD`, `WORKSPACE`, `CMakeLists.txt`, `meson.build` and the ignore-style dotfiles. PlantUML stays highlighted source; nothing is rendered.

**Types.** Of the 181 suffixes, 46 are declared by the system (`CoreTypes` on the development Mac); all but `.ts` (MPEG-2 transport stream) and `.fs` (a file-system plug-in type) conform to `public.source-code`, and those two are listed below as collisions. The other 135, including eight of the base list that no system type covers (`rs`, `go`, `kt`, `kts`, `sql`, `tsx`, `jsx`, `cjs`), are declared in one imported type, `org.webmeister.spacepane.type.source-code`, conforming to `public.source-code`; it is imported (never exported) so Finder can route them on a Mac where no other app declares them. Another app's declaration of the same suffix wins or ties; either way it conforms to source code.

**Collisions, none taken from another format.** `.ts` (MPEG-2 transport stream), `.m` (MATLAB or Objective-C), `.pl` (Perl or Prolog), `.v` (Verilog or Coq), `.d`, `.r`, `.s`, `.fs` (also GLSL) and `.sc` stay source code with the reading that matches the system declaration or the larger user base. `.cls`, `.sty`, `.bib`, `.mmd`, `.map` and `.edn` (Adobe's type) are not claimed; `.sub` belongs to MicroDVD. `.lock` is not claimed as a suffix at all: lock files are recognized by exact name only. A suffix Quick Look types as something else (for example `.ts`) may still go to another provider; only `FormatCatalog.classify` inside this extension is certain.

## INI configuration (`config.ini`)

`.ini`, `.cfg`, `.conf`, `.properties`, `.xcconfig` and the names `.editorconfig`, `.gitconfig`, `.gitmodules`, `.npmrc`, `.pypirc`, `.pylintrc`, `.flake8`, `.coveragerc`, `.hgrc`, `.my.cnf`, `my.cnf`. Type: an imported type conforming to `public.text` plus the optional system alias `com.apple.xcode.configsettings`. The adapter accepts any text, because `.conf` and `.cfg` hold many grammars; the renderer builds a sections→keys outline (global keys first, `key = value`, `key: value`, `key value`, comments, indented or backslash continuation) and declines it, with the structure notice and concealed source, when a line cannot be a setting (a stray brace, `server {`). Credential-bearing names are included only because tests prove their forms are concealed (below).

**Privacy.** INI uses structural privacy. The shared plain-text heuristic treats `password =` with no value, a common placeholder, as the start of a multi-line value and conceals the rest of the file, so `INIPrivacyRanges` applies the same key rules per line: the key is decided from the text before the first delimiter (so `//registry.example/:_authToken=…` and npm's `_auth` work, with `auth`, `passphrase`, `requirepass`, `masterauth`, `cookie` and `sessionid` recognized as whole last segments so `bypass`, `compass` and nginx `proxy_pass` stay readable); the value and its continuation lines are concealed; whitespace directives such as `requirepass x` are handled; credentials in URLs are concealed. Tests cover `_authToken=`, `_auth=`, `_password=`, `password =`, indented, backslash and CRLF continuations and an empty placeholder that must not hide later sections.

## Logs (`text.log`)

`.log`, system type `com.apple.log`, thumbnail policy `content` (drawn by the thumbnails workstream). Decoration: timestamps (ISO 8601/RFC 3339, `2026/10/05`, bare times, syslog `Oct  5 14:03:22`, bracketed Apache/nginx `[05/Oct/2026:14:03:22 +0000]`), severities TRACE…FATAL/CRITICAL/PANIC and syslog names mapped to the existing syntax roles (debug and trace dimmed, info green, warning orange, error red), stack frames dimmed (Java/Kotlin/JS `at …`, `... N more`, Python tracebacks and their source line, Go goroutine stacks, Swift/Objective-C crash frames, Rust backtraces) and exception headlines flagged. A level word is colored only when upper case or delimited (`[error]`, `level=warn`), so prose is not.

Logs get their own concealment instead of the shared heuristic because that one hides the rest of the file after an assignment with no value (`Enter password:`) and the line number of every stack frame whose file name contains a secret word. The log pass keeps the `SecretFieldPolicy` key rules and ends a value at its line, except that a value opening an unbalanced `{` or `[` continues until balanced (bounded to 2,000 lines). It also conceals secret command-line flags (`--password x`, `--token=x`) and `Cookie`/`Set-Cookie` values; recognizable tokens, bearer values and, since 2026-10-06 ([decision 027](027-best-in-class-quality-program.md), Q-01), URL credentials are concealed by the shared stage for every text format, so the log, source and INI passes no longer carry their own URL scan. A line is skipped by the key scan only if it is an inert stack frame: every `:` must follow a known source-file suffix and precede digits, so `at password:123456` is still concealed.

## JSON with comments (`data.jsonc`)

`.jsonc`, `.json5`, `.code-workspace` and the names `tsconfig.json`, `jsconfig.json`, `.babelrc`, `.devcontainer.json`, `devcontainer.json`, `bun.lock` plus the prefixes `tsconfig.` and `jsconfig.` (comments are normal there). One lenient grammar covers both dialects: comments, trailing commas, unquoted and single-quoted keys, hexadecimal, signed, `.5`, `5.`, `Infinity`, `NaN`, `\x`, `\v`, `\0` and line continuations (`JSON5Lexicon` in contracts, shared by the adapter and the outline so token boundaries agree). Depth and node counts use the JSON budgets. Privacy is structural as for JSON (the value of every member whose decoded key is secret, whatever the key syntax), and a comment that assigns a secret is concealed with its delimiters left. Malformed input is `malformedDocument` with no raw fallback. Type: imported, conforming to `public.text`.

## Mapped existing formats

`Cargo.lock`, `poetry.lock`, `uv.lock`, `pdm.lock` use TOML; `Pipfile.lock`, `composer.lock`, `flake.lock`, `deno.lock`, `Package.resolved` use JSON; `Podfile.lock`, `pubspec.lock`, `.clang-format` use YAML; `Gemfile.lock`, `yarn.lock`, `mix.lock`, `go.sum`, `Cartfile.resolved` use plain text. `.entitlements` joins property lists (system type `com.apple.xcode.entitlements-property-list` exists only with Xcode, so an imported type conforming to the XML property-list type covers other Macs); `.xcstrings` and `.webmanifest` join JSON the same way. Each follows the switch of the format it maps to. Disabled formats never fall back to text.

## Captions

Five new formats share one bounded parser in contracts (`CaptionParser`), used by the adapter on raw text to validate and plan concealment and by the renderer on concealed text to list cues, so the two cannot drift. Cues mode shows `label: start → end` and the text lines joined by " / "; Source keeps every original character. A cue-count mismatch after concealment falls back to Source.

- **SubStation Alpha** (`.ass`, `.ssa`): `[Script Info]` first, sections, `Format:`/`Dialogue:` columns with the text field last, `H:MM:SS.cc` times, `end >= start`. `{\…}` override blocks are removed and `\N`, `\n`, `\h` interpreted in the cue list only; `[Fonts]` and `[Graphics]` data lines are skipped. `;` comments and `Comment:` events that assign a secret are concealed whole.
- **TTML** (`.ttml`, `.dfxp`): `<p begin end dur>` with clock and offset times shown as written, `<br/>` and `<span>`. A DOCTYPE or entity declaration is refused, external entities never resolve, depth, nodes and cue size are bounded. Because XML text can be hurt by line-based concealment, TTML uses structure-aware ranges (sensitive element and attribute names, comments, CDATA, instructions and any text run that assigns a secret) with markup left intact.
- **SBV** (`.sbv`): blocks with `H:MM:SS.mmm,H:MM:SS.mmm`.
- **LRC** (`.lrc`): `[mm:ss.xx]` stamps (several per line become several cues), `[ti:]`/`[ar:]`/`[al:]` tags as key/value rows, enhanced word times removed from cue text.
- **MicroDVD** (`.sub` text): `{start}{end}text` converted to clock times at the rate on a `{1}{1}fps` first line or 25 fps. VobSub `.sub` files share the suffix, so this adapter takes bytes and reports an MPEG program stream, a NUL byte or an invalid encoding as binary content, never as text. The imported type conforms to `public.data` because the suffix can be binary; a VobSub file therefore gets this product's binary-content message if Finder routes it here.

Syntaxes `.subStationAlpha`, `.timedText`, `.subViewer`, `.lyrics` and `.microDVD` were pre-added by the lead. SubRip and WebVTT are unchanged.

## Minified JSON

`JSONSourceAdapter` declares `allowsLongLines`. When the strict validator would throw `lineTooLong`, the document is scanned as strict JSON as before and then rewritten by `JSONReformatter`: a token-level rewrite (two spaces per level, `key: value`, empty containers inline, scalar arrays that fit in 100 source bytes on one line). Key order, duplicate keys, number lexemes and string escapes are copied byte for byte; the structural sensitive ranges are carried to output coordinates, so concealment matches the unformatted document. The result is checked against the line, line-length and output budgets, so a document with one giant string value still fails with `lineTooLong`. The presentation sets `isReformatted` and `PresentationNotices` adds the localized "Formatted for display". Formatting also applies to `package.json`, `.xcstrings`, `.webmanifest` and lock files that use the JSON adapter, not to JSONC (rewriting would drop comments).

## Partial previews (the shared-core edit)

Problem: oversized text failed with `inputTooLarge`. Design: an adapter opts in by conforming to `TextInputPolicyProviding` (`PartialInputContracts.swift`), returning `TextInputPolicy(partialBoundary:allowsLongLines:)`. Registrations, hosts and the other adapters are unchanged.

1. `PreviewPipeline` constructs the adapter (still after the enablement gate, still after cancellation) and asks its policy.
2. For a partial-capable adapter and a reader that conforms to `LeadingBytesReading`, `BoundedFileReader.readLeading` returns the first `maxInputBytes` bytes and the file size (`FileBytes.totalByteCount`) through the same no-follow descriptor, regular-file and change-detection checks as `read`. A reader without the capability stays strict.
3. `PartialTextPrefix` keeps the longest prefix that ends at a record boundary (after any line terminator; after a blank line for SRT, WebVTT and SBV; outside a quoted field for CSV), has at most `maxTextLines` lines and no line over `maxLineUTF8Bytes`, understands UTF-8 and BOM-marked UTF-16, and never cuts inside a multi-byte sequence or surrogate pair. When no complete record fits it throws `inputTooLarge`.
4. `TextPresentation.byteCount` counts the bytes shown; `truncatedSourceBytes` carries the file size; `PresentationNotices` shows "Showing the first %1$@ of %2$@" with locale-formatted byte counts.

Opted in: plain text, Source Code, logs, INI, CSV, TSV, JSON Lines, SubRip, WebVTT, SubStation, SBV and lyrics. Not opted in, and unchanged: JSON, YAML, TOML, environment files, XML, property lists, notebooks, JSONC, TTML, MicroDVD (binary path), Markdown, diff, archives, databases, MIDI, CAD. A file at or under the budget is never marked partial; a file that fits is still held to the line budget (only an oversized file is cut by it), so `maxTextLines` behavior for ordinary files is unchanged.

**Effect on existing formats.** Plain text, CSV, TSV, JSON Lines, SubRip and WebVTT previously failed with `inputTooLarge` above the budget and now show a prefix with a notice; JSON no longer fails on over-long lines (formatting) but still fails on size. `JSONLinesPipelineSharesCumulativeAndByteBudgets` asserted the old failure and now asserts a partial result plus the failure when even the first record cannot fit. `TextDecoder.decode` and `TextMetrics.validate` gained an `enforcesLineLength` parameter (default on). `FileBytes`, `ParsedTextDocument` and `TextPresentation` gained trailing optional fields with defaults. Everything else, including the adversarial corpus, is unchanged.

## Stretch: String Catalog table

For `data.json` text whose outline has `sourceLanguage` and a `strings` object, `SafeStringCatalogTable` derives a Key column plus one column per language (source language first) from the same concealed outline the JSON modes use; plural and device variations show an ellipsis and missing translations are empty. It opens first (the table rule) with Source and Outline still available. Limits are the delimited table's.

## Localization

18 keys in all 14 languages as drafts: `format.<id>.name` and `.description` for the eight formats, `preview.code.notice.truncated` and `preview.code.notice.reformatted`. No other UI literal was added. File contents, key names, timestamps and cue text are never translated. Native-speaker review is pending.

## What is not promised

- Finder routing: macOS chooses the provider per type. The imported types let Finder offer these suffixes when no other app declares them, nothing more. Dotfiles (`.npmrc`, `.gitignore`) are typed `public.data` and reach this extension only through the extension-free registration of [011](011-extensionless-files.md); executable-bit files are not covered.
- Thumbnails for the new formats (`text.log` asks for `content`; the thumbnails workstream draws it).
- Highlighting beyond lexical rules, and any language server, regex literal, heredoc or interpolation awareness.
- That a `.conf` or `.cfg` file is INI: an outline appears only when every line fits.
- Concealment of secrets that are neither assignments, URL credentials, command-line flags, cookie headers nor recognizable tokens (for example SQL `IDENTIFIED BY 'x'`, an nginx `add_header X-Key abc;`, prose).
- VoiceOver, translated layout and signed-host behavior.

## Alternatives rejected

- A registration flag for partial reads: it would edit existing registration lines owned by other families; an adapter-declared policy keeps registrations and the shared list unchanged.
- Parsing every dialect twice (adapter and renderer): the five new caption dialects share `CaptionParser` in contracts, following `DelimitedRecords`.
- A `.lock` suffix claim: it would route every lock file of any tool here.
- One imported type per source suffix (as another app does): one imported type for the suffixes no system type covers keeps three manifests small.
