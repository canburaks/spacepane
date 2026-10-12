# 020 — Ebooks, comics, web archives, notebook figures and the image pages view

Date: 2026-10-05. Status: implemented locally with package, pipeline, renderer and adversarial-corpus
evidence; Finder routing, thumbnails, VoiceOver and signed-host behavior are unverified. Evidence is in
[the validation record](../validation/ebooks-2026-10-05.md). This is the `ebooks` workstream of
[the competitor parity program](025-competitor-parity-program.md).

## Scope

Four independently switchable logical types, one extension of an existing type, and the first image
presentation:

| Format ID | Suffixes | Canonical type | Group | Thumbnail | Initial mode | Safe modes |
|---|---|---|---|---|---|---|
| `archive.comic-book` | `cbz` | imported `org.webmeister.spacepane.type.comic-book-zip` (conforms to `public.zip-archive`) | Containers | `content` | Pages | Pages, Summary, Source |
| `document.epub` | `epub` | system `org.idpf.epub-container` | Text | `content` | Rendered | Rendered, Source, Pages (cover) |
| `document.fictionbook` | `fb2` | imported `org.webmeister.spacepane.type.fictionbook` (conforms to `public.xml`) | Text | `content` | Rendered | Rendered, Source, Pages (cover) |
| `document.web-archive` | `mht`, `mhtml` | system `org.ietf.mhtml` | Text | `content` | Rendered | Rendered, Source |
| `text.jupyter-notebook` (existing) | `ipynb` | unchanged | Text | unchanged | Rendered | unchanged, plus Pages when figures exist |

`org.idpf.epub-container` and `org.ietf.mhtml` are declared by the system on the development Mac. Both also carry an
imported declaration (conforming to `public.data`) so the catalog still constructs them in a process that has not
loaded the system declaration, the same precedent as `org.w3.webvtt` and `org.sqlite.sqlite`. `.cbz` and `.fb2` have
only dynamic system types, so they use app-selected imported identifiers. These are declarations, not claims about
Finder's choice of provider. No root type (`public.data`, `public.item`, `public.content`) is claimed and nothing is
exported. CBR, CB7, MOBI/AZW, DjVu and `.fb2.zip` are out of scope (the program record explains why).

Everything is read through the existing pipeline: classification, the user's file-type policy before any read or
adapter construction, bounded read, adapter, shared privacy filter, presentation. The four new adapters use the
request-owned random-access input path (`RandomAccessFormatAdapter`), because their useful parts (a ZIP central
directory, a cover, a head window) are not the whole file.

## The image presentation contract, as used

`PreviewImage` (encoded bytes, validated pixel size, role, optional label) bypasses text concealment, so the contract
is deliberately narrow:

- **Only document content becomes a picture.** Pages (comics), a cover (EPUB, FB2) and saved figures (notebook
  `image/png` and `image/jpeg` outputs). Never SVG, HTML, web resources, inline book images, thumbnails taken from
  elsewhere in the archive or anything an adapter would have to render to obtain.
- **Validation without decoding.** `EmbeddedImageValidator` accepts JPEG, PNG, GIF, WebP and HEIC/AVIF by signature
  (never by suffix or declared media type), opens the container with `CGImageSourceCreateWithData`, requires an image
  type, and reads `kCGImagePropertyPixelWidth/Height` and the EXIF orientation through
  `CGImageSourceCopyPropertiesAtIndex`. Adapters never decode pixels. Orientations 5-8 swap the stored dimensions so
  the layout uses the displayed ones. An image fails validation (and is skipped, never an error) when either side is
  outside `1...16,384` (the shared limit), when width x height exceeds 100 megapixels (an additional ceiling so a tiny
  file cannot ask the renderer for gigabytes), when the container does not parse, or when it exceeds 8 MiB encoded.
- **Aggregate limits.** At most 500 images and `min(48 MiB, 4 x maxInputBytes)` of encoded image bytes per
  presentation (`DocumentLimits`/`ImageCollector`). The ceiling ends a list rather than skipping a page, because
  skipping silently reorders a comic. Request budgets bind first in practice: every ZIP member read is charged to the
  cumulative `maxInputBytes` read budget (1 MiB by default), so a default comic preview carries the first few pages
  and says how many exist. This is a deliberate consequence of the shared budget, not a promise to show whole comics.
- **Labels.** A comic page's `label` is its archive path. A path that looks like a secret assignment
  (`SecretFieldPolicy`) or is longer than 256 bytes gets no label. The view shows it only as a tooltip/accessibility
  hint.
- **Residual privacy risk.** Concealment cannot read pixels. A notebook figure or a book cover can legitimately show
  text that a text pass would have concealed. The picture is document content by definition of the extraction rule;
  the thumbnails workstream gates whether pictures leave the Pages mode at all (`showsContentThumbnails`). Nothing
  here removes that risk.

## Pages view (`.pages`)

`NativeImagePagesView` (registered under `// [ebooks]` in `SafeModeViewRegistry`; available when `modes.images` is not
empty) is a continuous vertical column inside an `NSScrollView`.

- **Layout** (`ImagePagesLayout`, pure value logic): every page frame is computed from `pixelWidth/pixelHeight` before
  any decode, fit to the available width, centered, and never magnified beyond 2x its native point size (so a small
  cover does not stretch across a wide window). A 22-point caption band sits under each picture. A binary search over
  page tops finds the visible range.
- **Lazy decode** (`ImagePageScheduler`, `ImagePageDecoder`): pictures within one viewport of the visible area are
  requested nearest first through `CGImageSourceCreateThumbnailAtIndex` with
  `kCGImageSourceCreateThumbnailFromImageAlways`, `kCGImageSourceCreateThumbnailWithTransform`,
  `kCGImageSourceShouldCacheImmediately` and a `kCGImageSourceThumbnailMaxPixelSize` that is never above 4,096 and keeps
  the decoded area at or below 8 megapixels. Decodes run in an `@concurrent` function, at most two at a time.
  Bitmaps farther than two viewports away are released, and a 192 MiB resident-bitmap budget evicts the farthest
  non-visible page first. A visible page that would not fit the budget stays a placeholder instead of exceeding it.
  `clear()` cancels every decode and drops every image; a late result for a replaced, released or cleared page is
  ignored (the scheduler delivers only for a task that is still the registered one). Closing the hosting window does the
  same.
- **Deviation from the brief's pixel rule, recorded.** The brief bounds `kCGImageSourceThumbnailMaxPixelSize` by
  `min(view width x backing scale, 4096)`. ImageIO applies that size to the longer side, so for a portrait page the
  literal rule would decode a page at roughly two thirds of the pixels its display width needs. The size requested is
  instead whatever fills the display width (aspect-aware), still capped by 4,096 and by 8 megapixels. The memory bounds
  the literal rule was protecting are kept by the area cap and the resident budget.
- **Accessibility.** Each page is an accessibility image element labelled "Page %1$@ of %2$@" (localized, numbers
  formatted for the presentation locale; the total prefers the archive's real page count over the pages carried), a
  cover is "Cover image", notebook figures are "Figure n of m", and a picture that cannot be decoded keeps an annotated
  placeholder instead of retrying. The scroll area carries the localized mode name and a keyboard hint.
- **Keyboard.** Down/Up (one line), Page Down/Up (90% of the viewport), Home/End, Command-Down/Command-Up
  (end/start), Right/Left (next/previous page), all only while the pages have keyboard focus. Amended 2026-10-06
  ([decision 027](027-best-in-class-quality-program.md), Q-75, owner decision D9): Space and Shift-Space are no
  longer handled anywhere in a preview, so Quick Look keeps them; Command-Up/Down are claimed through
  `performKeyEquivalent` only while the document container is first responder.

## Text documents

All three text formats produce Markdown with `syntax: .markdown`, so the Rendered mode applies unchanged and a later
Contents mode derives from the headings. The Markdown starts with YAML front matter (`title`, `author`, `language`,
`publisher`, `date`, `identifier`, `description`; `source` and `resources` for web archives). Values are collapsed to
one line, quoted when YAML could misread them, and never contain a newline, so a document cannot inject keys.

**Tolerant markup instead of `XMLParser`.** The brief suggested `XMLParser` with external entities disabled. The
formats here are routinely malformed (undeclared `&nbsp;`, HTML5 void tags, unclosed paragraphs), `XMLParser` aborts at
the first such error, and MHTML needs an HTML reader anyway. One bounded tokenizer (`MarkupTokenizer`) therefore reads
package files, XHTML, HTML and FB2. It never resolves a DTD, an entity declaration, an external subset or a processing
instruction (all skipped), decodes only numeric references, the five XML entities and a fixed table of common HTML
names, caps each tag at 64 KiB, 64 attributes and 4 KiB per attribute value, skips unterminated tags in linear time,
treats `script`/`style` (and FB2 `binary`) as raw text it discards, and charges work to the request's cooperative
checkpoint. `MarkupTreeBuilder` adds the shared depth and node budgets for structured files. Encodings are read from a
BOM, a MIME charset or the document's own declaration (`CFStringConvertIANACharSetNameToEncoding`); undecodable bytes
become replacement characters rather than failing a book. The intent of the brief (no external entity resolution,
bounded depth and nodes, graceful errors) is met; the specific API is not used.

**HTML to Markdown** (`HTMLMarkdownConverter`, a streaming state machine) keeps headings, paragraphs, line breaks, flat
and nested lists (eight levels), block quotes (eight levels), preformatted text in a fence that cannot be closed by its
own content, emphasis, code, and tables as pipe rows. Images become `![alt]()` (since 2026-10-06, decision 015 as amended by decision 027 Q-07; before that `[image: alt]`; brackets escaped, nothing when
there is no alt text) and links keep only their text. Dropped with their content: `script`, `style`, `iframe`,
`object`, `embed`, `form` (with its text), `svg`, `math`, `head`, `noscript`, `template`, `audio`, `video`, `canvas`, `applet`
and ruby annotations. No link target, image source or stylesheet is ever read, requested or shown.

**Privacy and escaping interact.** The native Markdown renderer reads a backslash escape before any other marker, so
the converter escapes characters it would otherwise interpret. An early version escaped every underscore, and the
pipeline test caught that `api_key = value` became `api\_key = value`, which the shared filter no longer recognized
(`SecretFieldPolicy` matches the spelling). Underscores inside a word are therefore left as written, and the filter's
credential patterns (`ghp_…`, `AWS_SECRET_ACCESS_KEY=…`) see the real text. The cost is how an intraword underscore
renders in the current inline reader; concealment takes priority. Lines are never padded or reflowed around secrets and
the shared filter alone decides what is concealed.

**Output bounds.** Generated Markdown stops at 240,000 UTF-16 units, 19,876 lines, a quarter below the output byte
budget, and 8 KiB per line (wrapped at spaces, hard split for an unbroken token). The 240,000-unit ceiling is below the
native Rendered view's 262,144-unit and 20,000-line limits, so an ordinary long book renders instead of falling back to
source; a test pins that relationship. Truncation is reported, not an error.

**Notices without a new contract field.** Adapters cannot localize and `TextPresentation` has no flags, so they record
neutral front-matter lines: `drm: true` and `partial: true`. `DocumentPresentationNotices` (under the `[ebooks]` marker
in `PresentationNotices`) reads only the leading front-matter block, only for these three formats, and writes the
localized status line. Comics carry their facts in the JSON summary (`pageCount`, `shownPages`, `partial`), localized
through `SummaryLabelSet.comicBook`, and the notice "Showing the first 3 of 1,200 pages." is derived from it.

### CBZ (`archive.comic-book`)

Image members of a ZIP (via the shared `ZIPArchiveReader`, `.list` encrypted-entry policy) in natural name order
(digit runs compare numerically, ASCII case-insensitive, exact spelling breaks ties; `NaturalOrder`). `__MACOSX`
folders, hidden files and folders, directories and non-image suffixes are ignored; a member whose bytes are not a valid
image is counted in `pageCount` but not shown. `ComicInfo.xml` (shallowest, at most 256 KiB, tolerant) supplies title,
series, number, writer and the declared page count (written as `declaredPageCount` only when it differs). The safe text
is the concealed JSON summary; a secret in a title is concealed by `SummaryWriter`. An oversized, over-budget or
corrupt page ends or interrupts the list as described above; an encrypted first page is `encryptedContent`; an archive
with no images still summarizes. Unsupported compression methods skip the page.

### EPUB (`document.epub`)

`META-INF/container.xml` names the package; the package supplies metadata, manifest, spine (manifest order when the
spine is empty), cover (`properties="cover-image"` wins over `<meta name="cover">`), navigation (`nav` document, else
NCX) and chapters. Hrefs are percent-decoded, resolved against the package, and never leave the archive; schemes and
`..` above the root resolve to nothing. Navigation titles become a leading heading only for a chapter that has none.
A missing chapter, cover or navigation file is skipped (`partial` for chapters); a missing container or package, or a
book with nothing to show, is `malformedDocument`. The cover read is limited to 60% of the read budget so text keeps
the rest, and a spent read budget keeps earlier chapters and reports `partial`.

**DRM.** `rights.xml` or `sinf.xml`, or an `encryption.xml` entry that is not font obfuscation
(`http://www.idpf.org/2008/embedding`, `http://ns.adobe.com/pdf/enc#RC` do not count), marks a book protected.
Protected and ZIP-encrypted chapters are omitted; content that is not markup (ciphertext without a descriptor) is never
decoded as text. The document carries `drm: true`, keeps its metadata and any readable chapters, and a protected book
with neither metadata nor readable text fails as `encryptedContent`. Nothing is decrypted, guessed or bypassed.

### FictionBook (`document.fictionbook`)

`title-info` and `publish-info` become front matter. Body titles and nested sections become headings (six levels),
epigraphs and cites become quotes, poems become stanzas, tables become pipe rows. The cover is the `<binary>` the
`coverpage` references, found by a bounded byte scan (no tree holds the base64), decoded and validated. A file larger
than the input budget is read as its first two thirds plus a one-third tail window, which usually holds the trailing
`<binary>` elements; the text is then partial.

### Web archives (`document.web-archive`)

A bounded MIME multipart reader (`MIMEMessage`: folded headers, quoted `boundary`/`start` parameters, nesting to four
levels, 500 parts, base64, quoted-printable, charset conversion, RFC 2047 subjects). The main part is the one named by
`start`, else the first `text/html`. Other parts are listed only as content type and URL host (`image/png
cdn.example.net ×2`), never a path, query or body. The page's own host is shown, never its full URL. Only the first
`maxInputBytes` of a larger file are read.

### Notebook figures — original implementation

`NotebookFigureExtractor` returns PNG and JPEG payloads of `display_data` and `execute_result` outputs as `figure`
images (base64, whitespace ignored, size-checked before decoding, validated like every image, skipped quietly when
invalid). Nothing else about notebooks changed: the exact source text, ranges, rendering and tests are as before, and
Pages is added to the modes without changing the initial one.

**Historical limitation, superseded by D16 below.** Notebooks arrived through the shared text path, whose 32 KiB line limit and 1 MiB input budget
apply before the adapter runs. A figure is therefore extracted only when its base64 line fits that limit (about 24 KiB
of PNG); a larger figure fails the notebook as `lineTooLong`, exactly as it did before this change (a pipeline test
documents it). Realistic matplotlib figures are larger, so the feature currently covers small plots and icons. Making
it effective needs a deliberate shared decision: register the notebook through the binary input path with its own
budget and replace extracted image payloads in the displayed JSON with an inert placeholder (the rendered view already
shows image outputs as "not shown"). That changes the shown source text and the registration line, which this
workstream does not own, so it is recorded as a request rather than implemented.


### Notebook image amendment — D16 / Q-15, 2026-10-08

The approved quality program moves notebooks to the existing binary input contract with an adapter-owned 16 MiB input and five-second budget. Strict UTF-8/BOM UTF-16 decoding records the actual source encoding. Raw JSON grammar, depth, nodes and notebook shape are validated before image extraction. The normal 2 MiB output, 32 KiB line and line-count ceilings still bind the transformed displayed source, including code, streams, text outputs and metadata.

Image MIME output string/array values become inert JSON `null` placeholders under their original keys. Every code unit outside those spans stays exact; sensitive ranges are remapped before the shared privacy filter. A localized provenance notice explains the replacement. Converted origin is reported only when a value changed. Notebook health reads the original validated structure; hidden-content findings scan the already-concealed displayed text and use its resulting line positions.

Saved PNG/JPEG figures from code-cell `display_data`/`execute_result` outputs remain available in Pages. Base64 alphabet, padding, unused tail bits, cumulative encoded length and decoded size are checked across array pieces before joining or decoding; aggregate collector limits precede allocation, and declared MIME must agree with the validated image signature. Other rich outputs remain inert. The feature executes nothing and performs no source writes. Package/AppKit validation includes realistic larger figures; actual Finder and image-footprint acceptance remain separate.

## Security and bounds, summarized

Read-only, offline, no extraction to disk, no sibling files, no scripts or styles, no entity expansion. Every loop
checks cancellation and the deadline; the shared adapter test proves each registration refuses to read after
cancellation or an expired deadline. ZIP members are read only after size limits (text 4 x `maxInputBytes` up to 4 MiB,
metadata 2 MiB, images 8 MiB), inflation is bounded by the declared size, and every member is CRC-checked. Zero
third-party dependencies; the only newly used system framework is ImageIO (already part of the macOS SDK and
extension-safe), imported by `PreviewFormats` and `PreviewRenderers`. No Package.swift change.

## Not promised

Finder routing or priority for any of these types; thumbnails (this record only sets the policy `content`; the
thumbnails workstream draws them); complete comics or books (previews are bounded by the request budget and say so);
page-turning fidelity, reading themes, resume position or font controls; WebP/HEIC/AVIF decoding on every supported
macOS 15 system (adapters validate only what ImageIO reports); readable interiors of CBR/CB7/MOBI/AZW/DjVu; any DRM
removal; rendering of web archives; Contents navigation (the markup workstream's mode); VoiceOver behavior in the
signed host; native-speaker review of the 25 new strings.

## Shared edits and requests

Marker insertions only: `TextAdapter` registrations, the Pages entry in `SafeModeViewRegistry`, the availability,
initial-mode and derivation lines in `SafePreviewModes`, the label set, the notice line, 17 `PreviewStrings.Key` cases,
one appearance sample and one host fixture per format. Generated files changed through their tools (manifests, string
catalog and `.lproj` files, appearance samples). One non-marker edit: `tools/test_localization.py` pins the exact set of
formatted string keys, so four new keys were appended to that set; each family adding formatted keys will touch the same
literal and the lead should union them. Requests: the notebook registration decision above; the thumbnails workstream
should read `TextPresentation.images` (first `cover`, else first `page`, else first `figure`); the markup workstream's
front-matter display may show the `drm` and `partial` lines, which the status notice already explains.

Amended 2026-10-10 (decision 027, Q-76; authored without a compiler, verification pending): truncated ebooks carry `chaptersShown` and `chaptersTotal` beside `partial`, and the notice reads "Showing n of m chapters" from those facts; a page that fails to decode draws a framed placeholder with a symbol and a localized label; the page column reports its top page and the preview shows "Page n of m" in the limits slot without announcing it; notebooks separate cell groups with thematic breaks and name a figure "Figure n, shown in Pages" only when the placeholder count equals the extracted figures.
