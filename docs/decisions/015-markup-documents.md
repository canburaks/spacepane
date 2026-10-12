# Markup documents

Date: 2026-10-05. Status: implemented locally; Finder routing, thumbnails, VoiceOver and signed-host behavior are not verified. Part of the [competitor parity program](025-competitor-parity-program.md); the gaps it closes are described in the [competitor landscape](../market/2026-10-05-competitor-landscape.md). The evidence is in [the markup validation record](../validation/markup-2026-10-05.md).

## Decision

Extend the native, inert Markdown rendering and add six text-document formats (LaTeX, BibTeX, AsciiDoc, reStructuredText, Org and Fountain). All of them produce one decoration model from already-concealed text, so the Rendered, Contents and References views never see source bytes. Nothing is compiled, evaluated, followed or loaded, and nothing claims to typeset: formulas are an acknowledged Unicode approximation and citation styles are acknowledged simplifications.

## One decoration model

`SafeMarkdownDocument` (rendered text, UTF-16 decorations, collected headings) is produced by `MarkupBuilder`, which owns the shared bounds. Every renderer in `PreviewRenderers/Markup/` writes through it; `NativeMarkdownStyling` is the only place that turns decorations into fonts, colors and paragraph styles.

- **Styles.** Headings, bold, italic, code and fenced code, strikethrough, quotes, table headers, math and display math, a distinct `diagramSource` for fenced Mermaid, front-matter block and keys, footnote marks and labels, list items (depth plus hanging-indent width) and list continuations, task markers, rules, dimmed source comments, definition terms, centered/trailing alignment, em indentation and right-to-left. Block and paragraph styles are applied before inline styles, so bold, italic and code compose on the face a heading or math span set.
- **Direction.** Right-to-left is decided once, in `MarkupBuilder.finish()`, for every dialect: a paragraph is right-to-left when its first strong character (UAX #9 rules P2 and P3, so list markers, digits and punctuation are skipped) is. Runs of such lines merge into one decoration; whole-line code, math, diagrams and rules stay left-to-right. Styling sets `baseWritingDirection = .rightToLeft` with natural alignment per paragraph, never a global direction.
- **Headings.** Level, plain title and the UTF-16 range of the title in the rendered text are collected while rendering. The range, not a search, is what Contents selects.
- **Footnotes.** Numbers are Unicode superscripts, so copying and VoiceOver need no baseline attributes; a localized "Footnotes" heading (also a Contents entry) and one line per note close the document.

### Bounds

| Bound | Value | When exceeded |
|---|---|---|
| Source and rendered text | 262,144 UTF-16 units each | Rendered is unavailable; Source remains, with the structure-fallback notice |
| Source lines (Markdown) | 20,000 | Rendered is unavailable |
| Decorations | 20,000 | Rendered is unavailable |
| Collected headings | 5,000 | Later headings are not listed; the document still renders |
| Footnotes | 1,000 | Later notes stay ordinary text |
| Front matter | 200 lines | Not treated as metadata |
| Inline spans (math, links) | 2,000 characters from the opener | The opener stays literal |
| Emphasis pairing | 400,000 steps per line, one stack per delimiter character | Remaining delimiters stay literal |
| Math span | 4,096 characters, nesting 24 | Shown as written, unconverted |
| Nesting of blocks | 8 (AsciiDoc, RST), 32 groups (LaTeX) | Content is read flat |
| BibTeX | 5,000 entries, 64 fields per entry, 8,192 units per value, 200 names per list | Later entries, fields and names are not read |

Every renderer returns nil instead of a partial document, except the explicit heading and footnote caps above.

## Native Markdown

New constructs: ordered and nested lists (depth from indentation, numbering from the first number), task lists (ballot-box glyphs), strikethrough, footnote references with a Footnotes section, GitHub alerts (`NOTE`, `TIP`, `IMPORTANT`, `WARNING`, `CAUTION`) with localized titles, thematic breaks, setext headings, YAML (`---`) and TOML (`+++`) front matter as a compact key/value block, math, definition lists, tables with or without outer pipes, nested block quotes, and a `diagramSource` decoration on ```` ```mermaid ```` fences so a later view can embed the diagrams workstream's renderer. Links, images and HTML stay inert: a link is its label with the target in parentheses as plain text, an image is its description only, HTML is literal and no attribute is ever a link.

Behavior changes to existing Markdown, each deliberate and covered by tests:

- **Rendered is the first view** for Markdown and every markup format; Source is one click away. (It was Source for Markdown.)
- **Emphasis** follows flanking rules, so `snake_case_name` and `2 * 3 * 4` stay literal and unmatched markers are not consumed. Previously an unmatched marker disappeared and styled the rest of the line.
- **Backslash** escapes only ASCII punctuation (`C:\Users` keeps its backslash).
- **Line terminators.** CRLF is one terminator; it used to produce a spurious blank line.
- **Tables** keep their last cell when the closing pipe is missing, and a header can lead into a table without a leading pipe.
- **Fenced lines** keep the inline-code decoration, as before, so the notebook renderer's tests and escaping rules are unaffected; the direction pass treats a line wholly covered by it as code.

The original implementation kept each source line as one output line. The 2026-10-07 reflow amendment below supersedes that behavior. The notebook renderer feeds this one, so notebook Markdown cells gain the new constructs; its own escaping of `\`, `` ` ``, `*`, `_` and `[` does not cover `$`, `~` and `^`, so an untrusted label such as a MIME type containing a well-formed `$x$` could render as math. That is formatting only; see the requests below.

## Math

`MarkupMath` converts a bounded subset of TeX to Unicode: Greek letters, operators, relations, arrows, delimiters, `\sin`-style function names, accents as combining marks, `\mathbb`, `^` and `_` as Unicode super and subscripts when every character has one (otherwise `^(…)` and `_(…)`, never silently dropped), `\frac{a}{b}` as `a⁄b` (parenthesized when an operand has several characters), `\sqrt{x}` as `√x`, `\sqrt[3]{x}` as `∛x`, matrices and `align` rows. Relations, arrows and binary operators get surrounding spaces. Unknown commands stay visible as `\name{…}`. It is styled distinctly (serif italic, the number color, centered for display math), and a status notice says formulas are approximated, not typeset. No TeX is expanded or executed, and macro definitions are not applied.

Where math is recognized: Markdown `$…$` (Pandoc rules, so `$5 and $6` stay text), `$$…$$`, `$$` blocks and ```` ```math ````; LaTeX `$…$`, `\(…\)`, `\[…\]`, `$$…$$` and the equation and align family; AsciiDoc `stem:[]`, `latexmath:[]` and `[stem]` blocks; reStructuredText `:math:` and `.. math::`; Org `$…$`, `\(…\)`, `\[…\]` and `equation`.

## Contents

`.contents` is available when a rendered document has at least two headings. `MarkupContentsView` lists them indented by level; a click, double click, or Return, Enter or Space on the selected row calls `navigate(.rendered, range)`, which switches to Rendered and selects the title. Arrow keys only move the selection, so a keyboard user can browse without leaving the list. Each row has a localized accessibility label ("Heading level 2: Title") and a hint. Copy writes the selected titles. For BibTeX each entry is a heading whose title is its citation key.

## Formats

All six are `presentation: text`, group Text, thumbnail `content`, enabled by default, and offer Rendered, Contents and Source. Source highlighting for them is `MarkupSourceTokens`; the code workstream's `SourceSyntaxTokens` needs one delegating line to use it (see requests).

| Format | ID | Suffixes | Rendered |
|---|---|---|---|
| LaTeX | `text.latex` | `tex ltx sty cls` | Sectioning (levels compress to the commands used), `itemize`/`enumerate`/`description`, quote, center, verbatim/`lstlisting`/`minted`, equation and align math, `\emph`/`\textbf`/`\texttt`/`\verb`, declarations such as `\bfseries`, footnotes, citations as `[key]`, tabular rows, comments dimmed, title block, paragraphs reflowed. The preamble is hidden when a document environment exists; `\input`, `\include`, `\includegraphics`, `\bibliography` and macro definitions are shown as dimmed source and never followed. Unknown commands lose their name and keep their argument. |
| BibTeX | `text.bibtex` | `bib` | Formatted reference list (APA) and a References mode with APA, MLA, Chicago author-date and IEEE. |
| AsciiDoc | `text.asciidoc` | `adoc asciidoc` | Section titles, header lines, nested bullet/ordered/check/description lists, listing, literal, passthrough (shown as code), quote, example/sidebar and open blocks, admonitions, tables, links and images as text, `stem` math, comments dimmed, `include::` and attribute entries shown and never applied. |
| reStructuredText | `text.restructuredtext` | `rst rest` | Titles (levels by first appearance), transitions, nested lists, definition and field lists, literal blocks, block quotes, line blocks, doctests, admonitions, `code-block`, `math`, grid, simple, list and CSV tables, `toctree` entries, footnote definitions, roles and hyperlinks as text. `include`, `literalinclude` and `raw` are shown and never run or emitted. |
| Org | `text.org` | `org` | Headings with their keywords, `#+` keywords (includes shown, never followed), source/example/quote/center/comment blocks, nested lists with checkboxes and description lists, tables with header, drawers and planning lines dimmed, links as text, footnotes, math. |
| Fountain | `text.fountain` | `fountain spmd` | Title page, sections, scene headings (listed in Contents; scene numbers stripped), action with its line breaks, character cues, parentheticals, dialogue, transitions, centered text, lyrics, notes (dimmed), synopses and boneyard (dimmed), dual-dialogue markers. |

### BibTeX and its styles

`SafeBibliography` is a bounded parser for entries delimited by braces or parentheses, braced and quoted values with nested braces, numbers, `@string` macros and `#` concatenation (with the month macros), `@comment` and `@preamble`; text between entries is ignored, the first duplicate field wins, and a missing closing brace is recovered at the next entry that starts a line. An unclosed value brace ends the file, as it does in BibTeX. Names follow the `First von Last`, `von Last, First` and `von Last, Jr, First` forms, with braced corporate names and `and others`. TeX in values becomes plain text (accents, dashes, quotes, protecting braces, `\emph`, inline math).

Styles are simplified renditions of APA 7, MLA 9, Chicago 17 author-date and IEEE for articles, books, proceedings, chapters, theses, reports and other entries, with the documented rules for initials versus full first names, ampersands and "and", and et al. thresholds (APA 21 or more authors, MLA three or more, Chicago more than ten, IEEE more than six). Missing fields degrade without placeholders (APA uses "n.d." and moves the title ahead of a missing author). Titles are used as written, because a program cannot know which words a style would lowercase, and a localized caption says to check the style guide. APA, MLA and Chicago sort by first author, year and title; IEEE keeps file order and numbers entries. DOIs and URLs are shown as plain text, never as links. The chosen style is view state only: never persisted, never sent to preferences.

## Catalog and types

None of these has a first-party system type, so each uses an app-selected imported type `org.webmeister.spacepane.type.<name>` that conforms to plain text (decision 004), with no exports and no root types. `.asc` is deliberately not claimed by AsciiDoc: it is armored PGP.

Checked on the development Mac with `UTType`: `.md`/`.markdown` resolve to `net.daringfireball.markdown`; `.mdown`, `.mkd`, `.mdx`, `.mkdn`, `.mdwn` (and others) only to types declared by third-party Quick Look applications (`com.quicklookpro.file.*`); `.mdtxt`, `.mdtext`, `.markdn`, `.ltx`, `.fountain` and `.spmd` have no declaration at all; `.tex`, `.sty`, `.cls` and `.bib` resolve to community identifiers (`org.tug.*`) that no system bundle declares; `.rst`/`.rest` to `org.python.restructuredtext`, `.rmd` to `com.rstudio.rmarkdown` and `.qmd` to `org.quarto.qmarkdown`. These are installed-app declarations, so which type Launch Services picks for a suffix is not deterministic across machines.

Consequences: the eight added Markdown suffixes extend the format's suffix list and its imported declaration. Four optional aliases are listed as supported types where those tools exist, never owned or exported: `org.tug.tex`, `org.python.restructuredtext`, `com.rstudio.rmarkdown` and `org.quarto.qmarkdown`. They are optional (`UTType` may be nil), and the lead may remove them if listing another developer's identifier is unwanted. Whether Finder routes any of these suffixes here is unverified. Thumbnail values for markup formats are `content`; the existing Markdown entry keeps its `generic` value, which the thumbnails workstream owns.

## Privacy

- The shared stage still conceals recognizable credential values and secret-key assignments in every document.
- **Markdown.** A leading front-matter block is planned on its own with the YAML or TOML rules plus the generic ones, and the body separately, so a block scalar in metadata hides only the metadata. A triple-quoted TOML secret is the exception: the shared policy cannot bound it and hides the rest of the document (fail closed).
- **LaTeX.** Control sequences with secret-like names (`\password{…}`, `\def\token{…}`, `\newcommand{\apikey}{…}`) conceal their arguments, and comments with secret-like assignments are concealed whole.
- **Org** conceals `#+PROPERTY:` lines whose property name looks secret and secret-like comments; **reStructuredText** conceals substitution definitions with secret-like names and such comments; **AsciiDoc** conceals secret-like `//` comments; **Fountain** plans the title page with the YAML rules; **BibTeX** uses the configuration rules for `name = {value}` fields.
- Rendered, Contents, References, copy and accessibility are derived only from `TextPresentation.text`, which is already concealed. The renderers carry no source bytes, and no format extracts images.

## Security

No network, no file reads beyond the previewed file, no sibling lookup, no process, no script, no macro or directive execution, no HTML. `\input`, `include::`, `.. include::`, `#+INCLUDE`, `\includegraphics` and `image::` are text. Adapters check cancellation and the deadline before touching input and in loops; every parser consumes at least one character per step.

## Shared files touched

Only at my own markers or through generators: `PreviewStrings.Key` cases, `NativePreviewMode.references` and its title, `SafePreviewModes` (the `references` model, Contents and References availability, the Rendered-first rule and derivations), the two view factory lines in `SafeModeViewRegistry`, one line in `PresentationNotices`, `StandardFormatAdapters.registrations`, the sample and fixture generators, the catalog (entries after `text.markdown`, plus the Markdown suffixes and aliases), Info.plists through `sync_manifests.py`, localizations through the tools, and `tools/test_localization.py`, whose list of formatted keys names the two new keys. `SafeSchemaLabels` needed no label set, because these formats have no summary fields.

## Requests for other owners

1. **Code workstream (`SourceSyntaxTokens.swift`).** Add `if let markup = MarkupSourceTokens.tokens(in: source, syntax: syntax, maximumUTF16Units: maximumUTF16Units, maximumTokens: maximumTokens) { return markup }` before the generic scan, so Source highlights the six syntaxes with their own lexers. Until then they use the generic lexical rules.
2. **Ebooks/lead (`SafeNotebookDocument.escapedInline`).** Also escape `$`, `~` and `^`.
3. **Interaction workstream.** None required: Contents navigation uses the existing `navigate` hook and the status line the existing notice hook.

## Not promised

- Typeset formulas, LaTeX packages, macros, cross-references, bibliography resolution, citation numbering from `\cite`, or rendering of figures.
- Exact conformance to any citation style guide; sentence-case conversion of titles; locale-specific style variants.
- AsciiDoc includes, attribute substitution and conditionals; reStructuredText substitutions, roles beyond the listed ones and Sphinx cross-references; Org `#+INCLUDE`, Babel evaluation, agendas and exports; Fountain dual-column layout and pagination.
- Rendered diagrams (the Mermaid decoration is a hook only), local or remote images, clickable links. Paragraph reflow is now implemented by the amendment below.
- Thumbnails (a separate workstream), Finder routing for any suffix, VoiceOver behavior in a signed host and native-speaker review of the translations are all unverified.

## Amendments (2026-10-06, decision 027)

Authored without a compiler or a Mac; verification is pending in the [pending-verification queue](../validation/pending-mac-verification.md).

- **Citation terms are English by design (owner decision D18; Q-08).** The References mode prints each style guide's own English terms in every interface language: "et al.", "n.d.", "(Ed.)" and "(Eds.)", ", editor" and ", editors", "edited by", "In ", "pp.", "vol.", "no.", edition ordinals ("2nd ed."), "Master's thesis", "Doctoral dissertation" and "Report No.". APA, MLA, Chicago and IEEE are English-language guides and these terms are their conventions, so a translation would print wording that no guide prescribes. `BibliographyFormatter` therefore keeps them as literals, outside `PreviewStrings`: this is a recorded, scoped exception to the rule that every app-authored string is localized. The References notice says so in a second sentence, "Citation terms follow each style guide’s English conventions." (`preview.markup.references.languageNote`), shown with the style caveat as one status line in Rendered and References. Style names, the caveat, the control labels and the accessibility label stay localized.
- **Images are drawn as a localized marker (Q-07, DM-18).** A Markdown image is one dimmed marker, "Image: description" (`preview.document.imageMarker`), replacing "an image is its description only" above. The destination is never shown, followed or kept. The ebook, FictionBook and web-archive converters now write the inert form `![description]()` instead of `\[image: description\]` (this supersedes the image sentence of [decision 020](020-ebooks-comics-and-images.md)); the description is escaped as other prose is (plus its closing bracket), so the shared privacy filter still conceals it. AsciiDoc, reStructuredText, LaTeX and Org keep their dimmed macro lines.
- **Converted documents show localized metadata (Q-07, DM-01).** For the formats in `DocumentPresentationNotices.documentFormats` the Rendered view labels the adapter-written fields (title, author, language, publisher, date, identifier, description, source, resources) in the interface language and does not show the machine flags `drm: true` and `partial: true`, which the status line already states. The flags are read from the safe text, not from the rendered text, so those notices are unchanged. A file's own front matter is never rewritten.
- **The offline notice is counted, not constant (Q-14, DM-06, DM-16).** The unconditional "Offline preview. External resources are not loaded." line is replaced by a label-colon line such as "Images not loaded: 2 · Linked files not loaded: 1", shown in Rendered only and only when a renderer left something out (owner decision D8: counted text stays plural-free until the plural tooling lands). Renderers count what they show as inert text and never load: Markdown images (a URL scheme or `//` is remote, `data:` is embedded and not counted, anything else is local; an image without a destination, the converters' form, is not counted), AsciiDoc `image::`, `image:` and `include::`, reStructuredText `image`, `figure`, `include` and `literalinclude`, LaTeX `\includegraphics`, `\input` and `\include`, and Org `#+INCLUDE` and description-less image links. Only counts are kept, never a destination. The web archive's `resources` front-matter value is a bounded display summary and is not counted. The math notice shows in Rendered only; the style caveat in Rendered and References only, once (the caption inside the References view is gone).

## Reading layout amendment (2026-10-07; Q-71, owner D2)

Rendered prose uses the system text face at the configured size, 1.4 line height, forced word wrapping and a centered measure of about 70 average advances applied through native text-container insets. The chosen code font applies to code spans/fences and Source. The source-line gutter and Go to Line are hidden in Rendered. Typography preferences and their schema are unchanged. Offscreen AppKit tests cover styling, resizing, Source restoration and safe selection/copy; actual Finder and VoiceOver review remain open. Paragraph soft-break reflow is a separate Q70 change.

## Paragraph reflow amendment (2026-10-07; Q-70)

Markdown paragraph soft breaks join with one space before inline parsing. Explicit two trailing spaces or an unescaped terminal backslash preserve a hard line break with its marker removed; escaped backslash pairs stay literal. Structural block boundaries and blank paragraphs remain separate. Same-depth quote prose follows the same rule without crossing quote blanks, depth changes, alert titles or other structural lines. Notebook Markdown cells inherit this behavior; fenced/code-cell contents keep their exact lines. The source presentation is unchanged. UTF-16 decorations/Contents ranges and direction are computed from the final bounded derived text; cancellation rejects the derived document. Tests and remaining host gates are in [the implementation record](../validation/quality-program-implementation-2026-10-07.md).
