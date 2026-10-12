# 016 — Native Mermaid and draw.io diagrams

Date: 2026-10-05. Status: implemented in the package and companion renderer; Finder routing, thumbnails and
signed-host behaviour are not verified (see [the validation record](../validation/diagrams-2026-10-05.md)).
Part of the [competitor parity program](025-competitor-parity-program.md).

## Context

Unfold draws Mermaid files as zoomable diagrams, Super Quick Look adds Mermaid, PlantUML and draw.io, and Peek and
QLMarkdown render Mermaid inside Markdown. All of them use a web renderer. This product draws natively: no web view,
no script engine, no network. A diagram file is untrusted text, so the drawing must be a pure function of bounded,
already-concealed data.

PlantUML is out of scope: rendering needs Java or a remote server, and the competitor uploads the file. It stays
highlighted source.

## Decision

Two catalog formats share one diagram pipeline.

| Format ID | Suffixes | Type | Group | Thumbnail | Presentation |
|---|---|---|---|---|---|
| `text.mermaid` | `.mmd`, `.mermaid` | imported `org.webmeister.spacepane.type.mermaid` (conforms to `public.plain-text`) | text | `content` | Source + Diagram |
| `data.drawio` | `.drawio`, `.dio` | imported `org.webmeister.spacepane.type.drawio` (conforms to `public.xml`) | text | `content` | Source + Diagram |

macOS has no system type for either suffix (checked with `UTType(filenameExtension:)` and CoreTypes), so both are
imported declarations exactly like the existing ones (decision 004); nothing is exported and no root type is claimed.
Both are on by default and have the usual per-type switch. Both sit in the File Types "text" group: the companion
model check hard-codes the member list of the "structured" group, so adding the draw.io type there would have broken
it, and that file belongs to the settings workstream. `TextSyntax.mermaid` and `.drawio` select the
presentation. `thumbnail: content` is a policy statement for the thumbnails workstream: the drawing function below
needs no AppKit or main-actor state, so a thumbnail may draw the diagram from concealed text. If that workstream draws
only a text excerpt instead, the policy is still valid.

### Layers (separation of concerns)

1. **Adapters** (`PreviewFormats/Diagrams/`) validate bounds and supply concealment. They know nothing about drawing.
2. **Parsers and layout** (`PreviewRenderers/Diagrams/`) read only the *concealed* `TextPresentation.text` and produce
   a `SafeDiagram`: a semantic model, a laid-out `DiagramScene` of primitives, and accessibility facts.
3. **Drawing** (`DiagramDrawing`) paints a scene into any `CGContext` with Core Graphics and Core Text.
4. **View** (`NativeDiagramView` / `DiagramCanvasView`) adds zoom, pan, fit, focus and accessibility.

The derived Diagram mode follows decision 007: the view consumes a model derived from concealed text, never source
bytes. If parsing or layout fails (unsupported diagram type, syntax error, limit) there is no Diagram mode, the
existing structure-fallback notice appears and Source stays available.

## Mermaid

The parser is written from the public Mermaid syntax documentation (original code, no dependency).

**Supported.** `flowchart`/`graph` with `TD`/`TB`/`BT`/`LR`/`RL`; node shapes `[ ]`, `( )`, `(( ))`, `((( )))`,
`{ }`, `{{ }}`, `[[ ]]`, `[( )]`, `([ ])`, `>]`, `[/ /]`, `[\ \]`; links `-->`, `---`, `-.->`, `==>`, `--o`, `--x`,
`<-->`, `o--o`, longer forms, `~~~` (layout only), labels as `|text|`, `-- text -->`, `== text ==>`, `-. text .->`;
chains, `&` groups, `subgraph … end` (nested, with ids, titles and `direction`), edges to a subgraph; `%%` comments,
`%%{…}%%` directives and front matter (skipped); `<br/>`, entity codes and quoted labels. `sequenceDiagram` with
participants and actors (aliases), the messages `->>`, `-->>`, `->`, `-->`, `-x`, `--x`, `-)`, `--)`, `<<->>`, notes
(`left of`, `right of`, `over`), `loop`/`alt`/`else`/`opt`/`par`/`and`/`critical`/`option`/`break` frames; activations,
`autonumber`, `title` and links are recognized and ignored. `pie` with `showData`, `title` and slices. `stateDiagram`
and `stateDiagram-v2` with states, descriptions, `[*]` markers, labelled transitions, choice/fork/join, notes and
composite states (frames, each with its own markers and optional `direction`). `classDiagram` (stretch item) with
classes, annotations, attributes and methods in separate compartments, generics (`List~int~`), namespaces (flattened),
notes, and the UML relations `<|--`, `--|>`, `*--`, `--*`, `o--`, `--o`, `-->`, `<--`, `--`, `..>`, `<..`, `..|>`,
`<|..`, `..` with multiplicities and labels. `erDiagram` (stretch item) with entities, aliases, typed attributes
(keys and comments) and the crow's-foot cardinalities `||`, `|o`/`o|`, `}|`/`|{`, `}o`/`o{` on solid or dashed
relationships with labels.

**Recognized and ignored, never executed:** `classDef`, `class`, `style`, `linkStyle`, `click`, `callback`, `accTitle`,
`accDescr`, `:::class` suffixes and `@{ … }` attribute blocks. `click` hrefs are not followed.

**Unsupported (no Diagram mode):** every other diagram type (`gantt` — the third stretch item, not implemented —
`journey`, `mindmap`, `timeline`, `gitGraph`, C4 and so on), the word spellings of ER cardinalities, single-line
class bodies (`class A { +x }`), Mermaid themes and configuration, markdown-formatted text, icons and images.

## Layout

One layered layout serves flowcharts, state, class and entity-relationship diagrams (the last two as `record` nodes
with compartments and UML or crow's-foot line ends); sequence and pie diagrams have their own geometry. Everything
is deterministic and bounded, because the renderers have no `RequestContext`.

- **Layered** (`LayeredLayout`): unique ordered pairs; cycles broken by an iterative depth-first search; longest-path
  ranks with sources moved next to their nearest successor; dummy nodes for edges spanning several ranks;
  breadth-first initial order; 12 barycenter sweeps (alternating direction, stable ties); coordinates from 8
  relaxation passes plus one two-sided pass, each solved exactly by pool-adjacent-violators so order and minimum gaps
  hold; rank positions from the thickest node per rank. Rank and order axes are abstract and mapped to x/y for the
  four directions.
- **Clusters** (`GraphLayout`): a subgraph or composite state is laid out on its own, becomes one box in its parent and
  is framed afterwards, so frames never overlap foreign nodes. Edges are routed at the outermost scope containing both
  endpoints and finish on the real endpoint, so a link into a subgraph still reaches its inner node.
- **Routing:** polylines through the dummy nodes, clipped to the shape border (rectangle, ellipse, diamond), rounded at
  joints; parallel edges fan sideways; self loops draw beside the node; labels sit on the route midpoint on a
  background chip; arrowheads, circles and crosses at either end.
- **Sequence** (`SequenceLayout`): columns grow until every message label and note fits between its lifelines, items
  stack downward, frames and `else` dividers wrap their items (outer frames drawn wider), participant boxes at both ends.
- **Pie** (`PieLayout`): slices in descending order from twelve o'clock, clockwise, locale-formatted percentages,
  legend with `showData` values written as in the file.

| Limit | Value |
|---|---|
| Concealed source | 512 KiB, 20,000 lines |
| Nodes / edges / clusters / cluster depth | 2,000 / 5,000 / 500 / 16 |
| Label | 400 characters, 12 lines |
| Dummy nodes / ranks | 20,000 / 2,500 |
| Sequence participants / items | 64 / 2,000 |
| Pie slices | 100 |
| Scene extent | 300,000 points per side |
| draw.io cells / vertices / depth / style pairs | 5,000 / 2,000 / 32 / 64 |
| Accessibility children / listed connections | 500 / 100 |

Any breach declines the diagram; nothing is laid out partially.

## draw.io

The adapter is a *binary* adapter. A compressed page is one base64 line that is routinely longer than the 32 KiB
per-line limit the text path applies to decoded text, so bytes are decoded by the adapter (UTF-8, with or without a
byte-order mark, or UTF-16 with one) and the line limit applies to the normalized output instead.

`DrawioDocumentReader` reads `<mxfile>` with `XMLParser` (external entities and URLs never resolved, DTDs and entity
declarations refused before parsing, comments and CDATA allowed) and takes the first `<diagram>`:

- a plain `mxGraphModel` child or a bare `mxGraphModel` root;
- compressed text: base64 → raw DEFLATE (`BoundedDecompression.rawDeflate`, read-only use, output cap three times the
  output budget before percent-decoding) → percent-decoding → XML, checked again for declarations;
- percent-encoded text without compression.

`DrawioModelWriter` re-writes the model as normalized XML, one element per line with attributes in a fixed order,
while recording exact UTF-8 ranges for concealment (`usesStructuredPrivacy`). Oversized values are shortened and
`key=value` pairs of a style string longer than 512 bytes (embedded image data) are dropped. The number of pages is
carried in `ParsedTextDocument.sourceRecordCount`; `PresentationNotices` shows a localized "Showing page 1 of N" line
when N > 1. Only the first page is shown; a page picker is not implemented.

The renderer draws vertices from `mxGeometry` with parent offsets applied (containers, groups, layers, `visible="0"`),
the shapes rectangle, rounded, ellipse, rhombus, triangle, cylinder, hexagon, parallelogram, swimlane (header side
and size), note and text-only, edges between shape borders (waypoints, floating `sourcePoint`/`targetPoint`, elbow
routing for orthogonal styles, arrowheads, dashed), `object`/`UserObject` wrappers, HTML labels reduced to text, and
edge-label cells positioned by relative geometry. Unknown shapes draw as rectangles. Document colors, images, links,
rotation and fonts are not applied: the preview theme controls every color, which keeps text legible in light, dark,
High Contrast and Increase Contrast.

## Privacy

- **Mermaid** (`MermaidPrivacyRanges`, structured). A secret-like assignment (`password: …`, `Client Secret = …`,
  `<b>Token</b>: …`) inside a bracketed, quoted or pipe-delimited label is concealed only up to the delimiter that ends
  that label — where Mermaid itself ends it — so `A[Token: JWT] --> B` keeps its edge and `B`. The shared line-level
  policy would have removed the rest of the line and left a silently incomplete diagram. Everywhere else (comments,
  directives, front matter, messages, notes, descriptions) the value runs to the end of the line, and a value that may
  continue (open brace, unbalanced quote, empty value before nested lines) conceals the rest of the file. The shared
  filter still conceals recognizable credential values anywhere.
- **draw.io** (`DiagramLabelPrivacy` in the writer). Every attribute value is scanned for such assignments (HTML-aware:
  tags are skipped and `<br>`/`<div>` end a line); attributes whose *name* is secret-like, such as `apiKey` on an
  `object`, are concealed whole.
- Derived models are built from concealed text only. Pictures are never extracted (`PreviewImage` bypasses text
  concealment), and style images are dropped.
- Thumbnails stay content-free until the thumbnails workstream draws from concealed text through the module API.

## Security and failure behaviour

No script, link, image, font or network access. Parsers are linear in the input apart from the bounded layout loops;
cycles, deep nesting, entity bombs, decompression bombs, corrupt base64/deflate/percent-encoding and oversized
coordinates fail with typed errors (`PreviewFailure.malformedDocument`, `.outputTooLarge`, `.tooManyNodes`,
`.structureTooDeep`, `.inputTooLarge`) or decline the diagram. Adapters call `context.checkpoint()` before any input
access and inside every loop. Nothing is written to disk. Parsing and layout of the derived model run when the safe
presentation is built (as for every other derived mode) and are bounded by the limits above; drawing is
nonisolated Core Graphics and Core Text.

## Module API (Markdown fences, thumbnails)

```swift
public struct SafeDiagram: Equatable, Sendable {
    public static func parse(mermaid safeSource: String, environment: DiagramEnvironment = .init()) -> SafeDiagram?
    public static func parse(drawio safeSource: String, environment: DiagramEnvironment = .init()) -> SafeDiagram?
    public func laidOut(with environment: DiagramEnvironment) -> SafeDiagram?   // re-measure for another font/locale
    public func draw(in context: CGContext, size: CGSize, palette: DiagramPalette, isFlipped: Bool = false)
    public var kind: Kind; public var contentSize: CGSize; public var nodeCount: Int; public var connectionCount: Int
}
public struct DiagramPalette  // standard(isDark:highContrast:) or background/foreground/accents
public struct DiagramEnvironment  // DiagramFont (family or system, size) + Locale
```

`parse(mermaid:)` returns `nil` for unsupported types, syntax errors and limit breaches, and takes **concealed** text:
the Markdown workstream passes the fenced block's text from the already-concealed Markdown presentation, and renders
either by embedding `NativeDiagramView`-style drawing (`DiagramCanvasView` for zoom) or by drawing into an image with
`draw(in:size:palette:)`, which fits and centers the diagram on the palette's background and needs no view. A fence that
does not parse stays a code block. `DiagramPalette(background:foreground:accents:usesColor:isHighContrast:)` derives
every role from background and foreground, so a palette built from the preview theme covers all appearances.

## Shared-file edits

Only the lead-defined marker points were used (`// [diagrams]` in `TextAdapter`, `SafePreviewModes` ×4,
`SafeModeContentView`, `PreviewStrings`; `# [diagrams]` in the appearance-sample and host-fixture generators). Edits
outside the markers, each required by the work:

- `PresentationNotices.swift` had no `[diagrams]` marker; one was added at the start of `lines(for:locale:)` (the
  draw.io page notice).
- `Package.swift` gained one test target, `PreviewDiagramsTests`, because the adapter→renderer tests need both modules.
- `tools/test_localization.py` lists every formatted resource key; the six new keys were added.

## Not promised

Finder routing or priority for `.mmd`, `.mermaid`, `.drawio` or `.dio`; thumbnail behaviour; VoiceOver behaviour;
native-speaker review of the translations of the 26 new keys; behaviour in the signed extension host; visual parity with
mermaid.js or diagrams.net; any Mermaid feature or diagram type listed as unsupported; draw.io colors, images, links,
custom shapes, rotation, layers UI or other pages; PlantUML. Layouts are readable, not identical to the reference
renderers.
