import Foundation
import PreviewContracts

enum NativePreviewMode: Hashable {
    case source, outline, records, rendered, summary, table, profile, cues, invisibles
    /// Heading navigation for rendered documents.
    case contents
    /// A native diagram drawn from concealed diagram source.
    case diagram
    /// Bounded embedded images such as comic pages or a cover.
    case pages
    /// A sortable table of listed files with kind, size and date columns.
    case files
    /// Listed paths nested into their folders.
    case tree
    // [workstream modes] Add a mode below its marker and its title/order/default in PreviewModePolicy.
    // [markup]
    case references
    // [diagrams]
    // [listings]
    // [ebooks]
    // [data]
    /// Coordinates drawn without a map.
    case plot
    /// The first rows of a columnar file, beside its schema table.
    case rows
    // [packages]
    /// An application icon extracted from a package, drawn by its own view.
    case icon
    // [code]
    var title: PreviewStrings.Key { PreviewModePolicy.title(for: self) }
}

struct SafePreviewModes {
    var outline: [SafeOutlineNode]?
    var records: [SafeOutlineNode]?
    var summary: [SafeOutlineNode]?
    var markdown: SafeMarkdownDocument?
    /// Numeric facts from the same successful notebook render, without parsing JSON again.
    var notebookFacts: PresentationFacts = .none
    var table: SafeTable?
    /// Present exactly when `table` is; the profile itself is computed when Profile is first shown.
    var profile: LazyDataProfile?
    var cues: [SafeOutlineNode]?
    /// Bounded encoded images carried by the presentation; views decode them lazily.
    var images: [PreviewImage] = []
    /// Document pictures shown by Pages: covers, pages and figures. Icons have their own mode.
    var pageImages: [PreviewImage] { images.filter { $0.role != .icon } }
    // [workstream mode models] Declare each derived model on its own line below your marker.
    // [markup]
    /// Formatted bibliography derived from concealed BibTeX; the References mode displays it.
    var references: SafeBibliography?
    // [diagrams]
    /// A diagram parsed from concealed Mermaid or draw.io text; nil when unsupported or invalid.
    var diagram: SafeDiagram?
    /// Which of a Markdown file's diagram fences `diagram` was parsed from, found with it (Q-77); nil for a diagram
    /// that is the whole file.
    var diagramReceipt: MarkdownDiagramFences.Receipt?
    // [listings]
    /// Listing-shaped summaries (folders, archives): a sortable table and a nested folder tree.
    var files: SafeTable?
    var tree: SafeListingTree?
    /// Numeric facts from the same successful listing parse, without source values.
    var listingFacts: PresentationFacts = .none
    // [ebooks]
    /// Page count the document reports for its image pages, when it can exceed the pages carried.
    var imagePageTotal: Int?
    // [code]
    // [data]
    var plot: SafePlot?
    var sampleRows: SafeTable?
    // [packages]
    /// Derived only when the findings report hidden characters, so clean previews pay nothing.
    var invisibles: SafeInvisibleText?
    var hasStructureFallback = false
    var available: [NativePreviewMode] { PreviewModePolicy.availableModes(in: self) }

    /// Mode selected when a new format is displayed; Source stays available for every safe text.
    func initialMode(for formatID: FormatID) -> NativePreviewMode {
        PreviewModePolicy.initialMode(for: formatID, in: self)
    }

    init(_ presentation: TextPresentation, locale: Locale) {
        images = presentation.images
        // [workstream derivations] Derive your models from concealed text below your marker;
        // each block must be self-contained and must not alter another family's models.
        // [markup]
        if let markup = MarkupRendering.models(for: presentation, locale: locale) {
            markdown = markup.document
            references = markup.references
            hasStructureFallback = markup.document == nil
        }
        // [diagrams]
        switch presentation.syntax {
        case .mermaid:
            diagram = SafeDiagram.parse(mermaid: presentation.text, environment: DiagramEnvironment(locale: locale))
            hasStructureFallback = diagram == nil
        case .drawio:
            diagram = SafeDiagram.parse(drawio: presentation.text, environment: DiagramEnvironment(locale: locale))
            hasStructureFallback = diagram == nil
        default: break
        }
        // [listings]
        if let listing = SafeListing.parse(presentation) {
            // Files and Tree come from the concealed summary JSON, never from source bytes.
            tree = SafeListingTree.build(listing)
            files = SafeListingFiles.table(listing, tree: tree, locale: locale)
            listingFacts = PresentationFactsProvider.facts(for: listing)
        }
        // [ebooks]
        imagePageTotal = ComicPageFacts.pageCount(in: presentation)
        // [code]
        if let derived = CodeSafeModes.derive(presentation, locale: locale) {
            if derived.replacesStructure {
                outline = derived.outline
                cues = derived.cues
                hasStructureFallback = derived.hasStructureFallback
            }
            table = derived.table
        }
        // [data]
        if let data = SafeDataPresentation.derive(presentation, locale: locale) {
            table = data.table
            sampleRows = data.sampleRows
            plot = data.plot
        }
        // [packages]
        if presentation.formatID == .jsonLines {
            records = Self.records(presentation, locale: locale)
            hasStructureFallback = records == nil
        } else if presentation.syntax == .json {
            outline = SafeStructuredText.json(presentation.text)
            hasStructureFallback = outline == nil
            if SafeSchemaLabels.formats.contains(presentation.formatID), let nodes = outline {
                summary = SafeSchemaLabels.localize(nodes, formatID: presentation.formatID, locale: locale)
                outline = nil
            }
            if presentation.formatID == .packageJSON, let root = outline?.first {
                // Wire names remain exact source identifiers, never localized or executed.
                let fields: Set<String> = ["name", "version", "description", "license", "private", "type", "main", "exports", "engines", "scripts", "dependencies", "devDependencies", "peerDependencies"]
                summary = root.children.filter { fields.contains($0.name) }
            }
            if presentation.formatID == .jupyterNotebook {
                // Cells are derived from the concealed notebook JSON, never from source bytes.
                // Rendered cells are the notebook's structure view; a large notebook may still lack Outline.
                let rendered = SafeNotebookDocument.renderResult(for: presentation, locale: locale)
                markdown = rendered?.document
                notebookFacts = rendered.map { PresentationFacts([.records($0.totalCells, .cells)]) } ?? .none
                hasStructureFallback = markdown == nil
            }
        } else {
            switch presentation.syntax {
            case .yaml, .toml: outline = SafeStructuredText.configuration(presentation.text, syntax: presentation.syntax); hasStructureFallback = outline == nil
            case .environment: summary = SafeStructuredText.configuration(presentation.text, syntax: .environment); hasStructureFallback = summary == nil
            case .markdown: markdown = SafeMarkdownDocument.render(presentation); hasStructureFallback = markdown == nil
            case .xml: outline = SafeXMLDocument.nodes(presentation.text); hasStructureFallback = outline == nil
            case .commaSeparated, .tabSeparated:
                table = SafeDelimitedTable.table(presentation.text, syntax: presentation.syntax, locale: locale,
                                                 isPartialRead: presentation.truncatedSourceBytes != nil)
                profile = table.map { LazyDataProfile(source: $0, locale: locale) }
                hasStructureFallback = table == nil
            case .subRip, .webVTT:
                // A concealed empty-valued assignment can collapse later cues; a count mismatch falls back.
                cues = SafeSubtitleCues.nodes(presentation.text, syntax: presentation.syntax, locale: locale,
                                              expectedCueCount: presentation.sourceRecordCount)
                hasStructureFallback = cues == nil
            default: break
            }
        }
        // Across families: a Mermaid fence in rendered Markdown also opens in Diagram (Rendered stays first).
        if diagram == nil, let markdown, let selection = MarkdownDiagramFences.selection(in: markdown, locale: locale) {
            diagram = selection.diagram
            diagramReceipt = selection.receipt
        }
        invisibles = SafeInvisibleText.make(for: presentation)
    }
    /// The table a table-style mode shows. Asking for Profile is what computes it.
    func displayedTable(for mode: NativePreviewMode) -> SafeTable? {
        switch mode { case .table: table; case .profile: profile?.value.table; default: nil }
    }
    func nodes(for mode: NativePreviewMode) -> [SafeOutlineNode]? {
        switch mode { case .outline: outline; case .records: records; case .summary: summary; case .cues: cues; default: nil }
    }
    private static func records(_ presentation: TextPresentation, locale: Locale) -> [SafeOutlineNode]? {
        guard presentation.text.utf16.prefix(262_145).count <= 262_144 else { return nil }
        var lines = presentation.text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        guard lines.count <= 20_000,
              presentation.sourceRecordCount == nil || presentation.sourceRecordCount == lines.count else { return nil }
        let invalid = Set(presentation.invalidRecordLines)
        var nodes: [SafeOutlineNode] = []
        var remainingNodes = 20_000
        var nextID = 0
        func numbered(_ node: SafeOutlineNode) -> SafeOutlineNode {
            let id = nextID; nextID += 1
            return .init(id: id, name: node.name, value: node.value, children: node.children.map(numbered), isDuplicateKey: node.isDuplicateKey, isIssue: node.isIssue)
        }
        for (index, line) in lines.enumerated() {
            let name = PreviewStrings.format(.previewRecord, arguments: [Int64(index + 1)], locale: locale)
            guard remainingNodes > 0 else { return nil }
            if invalid.contains(index + 1) {
                nodes.append(.init(id: nextID, name: name, value: PreviewStrings.format(.previewInvalidRecord, arguments: [Int64(index + 1)], locale: locale), isIssue: true))
                nextID += 1; remainingNodes -= 1
            } else {
                guard let root = SafeStructuredText.json(line, maximumNodes: remainingNodes)?.first else { return nil }
                let updated = numbered(root)
                remainingNodes = 20_000 - nextID
                nodes.append(.init(id: updated.id, name: name, value: updated.value, children: updated.children))
            }
        }
        return nodes
    }
}
