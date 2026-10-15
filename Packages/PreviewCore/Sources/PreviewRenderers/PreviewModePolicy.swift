import Foundation
import PreviewContracts

/// Chooses titles, available mode order and the first mode from already-safe capabilities.
/// Model derivation remains in `SafePreviewModes`; inspecting this policy never computes a profile.
enum PreviewModePolicy {
    static func title(for mode: NativePreviewMode) -> PreviewStrings.Key {
        switch mode {
        case .source: .previewModeSource
        case .outline: .previewModeOutline
        case .records: .previewModeRecords
        case .rendered: .previewModeRendered
        case .summary: .previewModeSummary
        case .table: .previewModeTable
        case .profile: .previewModeProfile
        case .cues: .previewModeCues
        case .invisibles: .previewModeInvisibles
        case .contents: .previewModeContents
        case .diagram: .previewModeDiagram
        case .pages: .previewModePages
        case .files: .previewModeFiles
        case .tree: .previewModeTree
        // [markup]
        case .references: .markupModeReferences
        // [diagrams]
        // [listings]
        // [ebooks]
        // [data]
        case .plot: .previewModePlot
        case .rows: .summaryRows
        // [packages]
        case .icon: .previewModeIcon
        // [openapi]
        case .endpoints: .previewModeEndpoints
        // [code]
        }
    }

    static func availableModes(in modes: SafePreviewModes) -> [NativePreviewMode] {
        var values: [NativePreviewMode] = [.source]
        if modes.outline != nil { values.append(.outline) }
        if modes.records != nil { values.append(.records) }
        if modes.summary != nil { values.append(.summary) }
        if modes.markdown != nil { values.append(.rendered) }
        if modes.table != nil { values.append(.table) }
        // Profile exists only where a profile was prepared (CSV and TSV), not for every family's table.
        if modes.profile != nil { values.append(.profile) }
        if modes.cues != nil { values.append(.cues) }
        // [openapi] Offered beside the JSON modes. It is never the initial mode: JSON still opens in Source.
        if modes.endpoints != nil { values.append(.endpoints) }
        // [workstream mode availability] Append your modes below your marker.
        // [markup]
        if (modes.markdown?.headings.count ?? 0) >= 2 { values.append(.contents) }
        if modes.references != nil { values.append(.references) }
        // [diagrams]
        if modes.diagram != nil { values.append(.diagram) }
        // [listings]
        if modes.files != nil { values.append(.files) }
        if modes.tree != nil { values.append(.tree) }
        // [ebooks]
        if !modes.pageImages.isEmpty { values.append(.pages) }
        // [code]
        // [data]
        if modes.plot != nil { values.append(.plot) }
        if modes.sampleRows != nil { values.append(.rows) }
        // [packages]
        if modes.images.contains(where: { $0.role == .icon }) { values.append(.icon) }
        // Last, and never the initial mode: it is a diagnostic view beside the safe presentations.
        if modes.invisibles != nil { values.append(.invisibles) }
        return values
    }
    /// Mode selected when a new format is displayed; Source stays available for every safe text.
    static func initialMode(for formatID: FormatID, in modes: SafePreviewModes) -> NativePreviewMode {
        // [workstream initial modes] Return early for your formats below your marker.
        // [markup]
        if modes.markdown != nil, MarkupRendering.rendersByDefault(formatID) { return .rendered }
        // [diagrams]
        if SafeDiagramFormats.all.contains(formatID), modes.diagram != nil { return .diagram }
        // [listings]
        if modes.files != nil {
            // A package summary lists its files too, but decision 017 keeps Summary first for the package
            // family (identity, signing and permissions lead); Files and Tree stay one click away. ZIP, TAR,
            // the other archives and folders open in Files (decision 014), and so does a package whose
            // Summary could not be built.
            return modes.summary != nil && SafeSchemaLabels.summaryFirstListings.contains(formatID) ? .summary : .files
        }
        // [ebooks]
        if formatID == .comicBook, !modes.images.isEmpty { return .pages }
        if DocumentPresentationNotices.documentFormats.contains(formatID), modes.markdown != nil { return .rendered }
        // [code]
        // [data]
        if let mode = SafeDataPresentation.initialMode(for: formatID, table: modes.table, sampleRows: modes.sampleRows, plot: modes.plot) { return mode }
        // [packages]
        if SafeSchemaLabels.formats.contains(formatID), modes.summary != nil { return .summary }
        if modes.table != nil { return .table }
        if formatID == .jupyterNotebook, modes.markdown != nil { return .rendered }
        return .source
    }
}
