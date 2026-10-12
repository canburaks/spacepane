import Foundation
import PreviewContracts

/// Limits belonging to a cached safe model. The facade combines them with byte/page limits in
/// its one bottom strip; content views own only their content, filters and native scrolling.
enum ModePresentationNotices {
    static func notices(for presentation: TextPresentation, modes: SafePreviewModes,
                        mode: NativePreviewMode, locale: Locale) -> [PresentationNotice] {
        // Profile's visible rows describe columns. Its inherited truncation and row count belong
        // to the cached source table. Only a selected Profile may ask for its computed row count.
        let table: SafeTable?
        switch mode {
        case .table, .profile: table = modes.table
        case .files: table = modes.files
        case .rows: table = modes.sampleRows
        default: table = nil
        }
        var notices: [PresentationNotice] = []
        // A partial listing is partial in every mode, including its safe summary Source. Prefer
        // cached flags over parsing that summary a second time; either model may survive alone.
        if modes.tree?.isPartial == true || modes.files?.truncation.contains(.partialListing) == true
            || table?.truncation.contains(.partialListing) == true {
            notices.append(.init(kind: .limit, text: PreviewStrings.text(.listingPartialNotice)))
        }
        notices += DrawnModeNotices.notices(modes: modes, mode: mode, locale: locale)
        guard let table else { return notices }
        if table.truncation.contains(.rows) {
            if mode == .profile {
                if let profile = modes.profile {
                    let count = profile.value.profile.profiledRows
                    notices.append(.init(kind: .limit, text: PreviewStrings.count(
                        .previewProfileShownRows, count, locale: locale)))
                }
            } else {
                let shown = table.rows.count
                let text: String
                if let total = exactRowTotal(for: presentation, table: table, mode: mode), total > shown {
                    text = PreviewStrings.count(.previewTableShownRowsOfTotal, shown,
                        additionalArguments: [total.formatted(.number.locale(locale))], locale: locale)
                } else {
                    text = PreviewStrings.count(.previewTableShownRows, shown, locale: locale)
                }
                notices.append(.init(kind: .limit, text: text))
            }
        }
        if table.truncation.contains(.columns) || table.truncation.contains(.cells) {
            notices.append(.init(kind: .limit, text: PreviewStrings.text(.previewTableLimitCaps)))
        }
        return notices
    }

    /// Only a whole delimited source has a grid fact describing this table's body rows. Adapter
    /// summaries and Profile grids describe different rows; prefix reads and lower bounds are not totals.
    private static func exactRowTotal(for presentation: TextPresentation, table: SafeTable,
                                      mode: NativePreviewMode) -> Int? {
        guard mode == .table, table.origin == .delimitedText, !table.isPartialRead,
              !table.truncation.contains(.partialListing), presentation.truncatedSourceBytes == nil,
              presentation.origin == .source,
              [FormatID.csv, .tsv].contains(presentation.formatID),
              [.commaSeparated, .tabSeparated].contains(presentation.syntax) else { return nil }
        for fact in presentation.facts.facts {
            if case .grid(let rows, _, let lowerBound) = fact, !lowerBound, rows >= 0 { return rows }
        }
        return nil
    }
}
