import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q51 one truthful limits strip", .serialized)
@MainActor
struct Q51LimitsStripTests {
    private let english = Locale(identifier: "en_US")

    @Test func rowsAndCellOrColumnCapsHaveSeparateTypedSentences() {
        let presentation = csv("a\n1\n2\n3\n")
        let table = SafeTable(columns: ["a"], rows: [["1"], ["2"]], truncation: [.rows, .columns, .cells])
        let notices = limits(presentation, table: table)
        #expect(notices == [
            .init(kind: .limit, text: "Showing the first 2 rows."),
            .init(kind: .limit, text: "Columns or long cells beyond the table limits are not shown.")
        ])
        #expect(!notices.contains { $0.text.contains("Source") })
    }

    @Test(arguments: [1, 2, 12_345]) func knownWholeDelimitedRowTotalsUseBothLocalizedCounts(shown: Int) {
        for locale in [english, Locale(identifier: "de_DE"), Locale(identifier: "tr_TR")] {
            for (format, syntax) in [(FormatID.csv, TextSyntax.commaSeparated), (.tsv, .tabSeparated)] {
                let total = 98_765
                let presentation = csv("a\n1\n", facts: .init([.grid(rows: total, columns: 1, rowsAreLowerBound: false)]),
                    format: format, syntax: syntax)
                let table = SafeTable(columns: ["a"], rows: Array(repeating: ["x"], count: shown), truncation: .rows)
                let notices = limits(presentation, table: table, locale: locale)
                let expected = PreviewStrings.count(.previewTableShownRowsOfTotal, shown,
                    additionalArguments: [total.formatted(.number.locale(locale))], locale: locale)
                #expect(notices == [.init(kind: .limit, text: expected)])
                #expect(expected.contains(shown.formatted(.number.locale(locale))))
                #expect(expected.contains(total.formatted(.number.locale(locale))))
                #expect(!expected.contains("%"))
            }
        }
    }

    @Test func partialReadsLowerBoundsAndSummaryGridsNeverSupplyAnExactRowTotal() {
        let exact: PresentationFacts = .init([.grid(rows: 98_765, columns: 1, rowsAreLowerBound: false)])
        let lower: PresentationFacts = .init([.grid(rows: 98_765, columns: 1, rowsAreLowerBound: true)])
        let table = SafeTable(columns: ["a"], rows: [["1"], ["2"]], truncation: .rows)
        var partialTable = table
        partialTable.isPartialRead = true
        var summaryTable = table
        summaryTable.origin = .dataSummary
        let partialListing = SafeTable(columns: table.columns, rows: table.rows, truncation: [.rows, .partialListing], origin: .listing)
        let cases = [
            (csv("a\n1\n2\n", facts: exact, truncatedSourceBytes: 3_000_000), table),
            (csv("a\n1\n2\n", facts: exact), partialTable),
            (csv("a\n1\n2\n", facts: lower), table),
            (csv("a\n1\n2\n", facts: exact), summaryTable),
            (csv("a\n1\n2\n", facts: exact, origin: .summary), table),
            (csv("a\n1\n2\n", facts: exact, format: .strings), table),
            (csv("a\n1\n2\n", facts: .init([.grid(rows: -1, columns: 1, rowsAreLowerBound: false)])), table),
            (csv("a\n1\n2\n", facts: .init([.grid(rows: 2, columns: 1, rowsAreLowerBound: false)])), table),
            (csv("a\n1\n2\n"), table),
            (plainPresentation("{}", format: .sqlite, syntax: .json), summaryTable)
        ]
        for (presentation, bounded) in cases {
            #expect(limits(presentation, table: bounded) == [.init(kind: .limit, text: "Showing the first 2 rows.")])
        }
        #expect(limits(csv("a\n1\n2\n", facts: exact), table: partialListing).map(\.text)
            == [PreviewStrings.text(.listingPartialNotice), "Showing the first 2 rows."])
        // Record provenance belongs to concealment, not a table's total.
        let records = TextPresentation(formatID: .csv, text: "a\n1\n2\n", lineCount: 3, byteCount: 6,
            encoding: .utf8, redactionCount: 0, syntax: .commaSeparated, sourceRecordCount: 98_765)
        #expect(limits(records, table: table).map(\.text) == ["Showing the first 2 rows."])
    }

    @Test func columnarRowsDoNotMistakeTheSchemaFactForTheirTotal() {
        let presentation = csv("a\n1\n", facts: .init([.grid(rows: 98_765, columns: 1, rowsAreLowerBound: false)]))
        var modes = SafePreviewModes(presentation, locale: english)
        modes.sampleRows = .init(columns: ["a"], rows: [["1"], ["2"]], truncation: .rows, origin: .dataSummary)
        #expect(ModePresentationNotices.notices(for: presentation, modes: modes, mode: .rows, locale: english)
            == [.init(kind: .limit, text: "Showing the first 2 rows.")])
    }

    @Test func onlyTheSelectedCachedGridContributesItsRowAndCellCaps() {
        let presentation = csv("a\n1\n")
        var modes = SafePreviewModes(presentation, locale: english)
        modes.table = .init(columns: ["a"], rows: [["1"]], truncation: .columns)
        modes.files = .init(columns: ["a"], rows: [["1"], ["2"]], truncation: .rows, origin: .listing)
        modes.sampleRows = .init(columns: ["a"], rows: [["1"], ["2"], ["3"]], truncation: .rows, origin: .dataSummary)
        #expect(ModePresentationNotices.notices(for: presentation, modes: modes, mode: .source, locale: english).isEmpty)
        #expect(ModePresentationNotices.notices(for: presentation, modes: modes, mode: .table, locale: english)
            == [.init(kind: .limit, text: PreviewStrings.text(.previewTableLimitCaps))])
        #expect(ModePresentationNotices.notices(for: presentation, modes: modes, mode: .files, locale: english)
            == [.init(kind: .limit, text: "Showing the first 2 rows.")])
        #expect(ModePresentationNotices.notices(for: presentation, modes: modes, mode: .rows, locale: english)
            == [.init(kind: .limit, text: "Showing the first 3 rows.")])
    }

    @Test func independentProfileSamplingKeepsItsProvenanceWithoutInventingASourceOmission() {
        let presentation = csv("a\n1\n")
        let source = SafeTable(columns: ["a"], rows: (0..<10_010).map { [String($0)] }, truncation: [])
        var modes = SafePreviewModes(presentation, locale: english)
        modes.table = source
        let profile = LazyDataProfile(source: source, locale: english)
        modes.profile = profile
        #expect(ModePresentationNotices.notices(for: presentation, modes: modes, mode: .profile, locale: english).isEmpty)
        #expect(profile.value.statusLines == ["Rows profiled: 10,000 of 10,010"])
    }

    @Test func profileNamesTheRowsItActuallyProfilesAndKeepsItsOwnSamplingProvenance() throws {
        let presentation = csv("a\n1\n", facts: .init([.grid(rows: 98_765, columns: 1, rowsAreLowerBound: false)]))
        let source = SafeTable(columns: ["a"], rows: (0..<10_010).map { [String($0)] }, truncation: .rows)
        var modes = SafePreviewModes(presentation, locale: english)
        modes.table = source
        let profile = LazyDataProfile(source: source, locale: english)
        modes.profile = profile
        for mode in [NativePreviewMode.source, .outline, .records, .rendered, .summary, .table, .cues, .invisibles,
                     .contents, .diagram, .pages, .files, .tree, .references, .plot, .rows, .icon] {
            _ = ModePresentationNotices.notices(for: presentation, modes: modes, mode: mode, locale: english)
            #expect(!profile.isComputed)
        }
        let notices = ModePresentationNotices.notices(for: presentation, modes: modes, mode: .profile, locale: english)
        #expect(profile.isComputed && profile.value.table.rows.count == 1)
        #expect(notices == [.init(kind: .limit, text: "Profile uses the first 10,000 rows read.")])
        #expect(profile.value.statusLines.contains("Rows profiled: 10,000 of 10,010"))
        #expect(!notices.contains { $0.text.contains("98,765") || $0.text.contains("Showing") })
    }

    @Test func partialListingAppearsOnceInFilesTreeAndSourceWithoutRepeatingInsideContent() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let presentation = listing(partial: true)
        host.view.display(.ready(presentation), locale: english)
        let notice = PreviewStrings.text(.listingPartialNotice)
        for mode in [NativePreviewMode.files, .tree, .source] {
            try select(mode, in: host.view)
            #expect(host.view.limitsLabel.stringValue == notice)
            #expect(!host.view.statusLabel.stringValue.contains(notice))
            #expect(occurrences(notice, in: host.view.displayedStatus) == 1)
            let listingViews = descendants(of: NativeListingFilesView.self, in: host.view).map { $0 as NSView }
                + descendants(of: NativeListingTreeView.self, in: host.view).map { $0 as NSView }
            for content in listingViews {
                #expect(!descendants(of: NSTextField.self, in: content).contains { $0.stringValue == notice })
            }
        }
        host.view.display(.ready(listing(partial: false)), locale: english)
        #expect(host.view.limitsLabel.stringValue.isEmpty && host.view.limitsLabel.isHidden)
    }

    @Test func eitherCachedListingModelCanReportPartialAndMultipleFlagsStillProduceOneNotice() throws {
        let presentation = listing(partial: true)
        var modes = SafePreviewModes(presentation, locale: english)
        #expect(modes.tree?.isPartial == true && modes.files?.truncation.contains(.partialListing) == true)
        let expected = [PresentationNotice(kind: .limit, text: PreviewStrings.text(.listingPartialNotice))]
        #expect(ModePresentationNotices.notices(for: presentation, modes: modes, mode: .source, locale: english) == expected)
        modes.tree = nil
        #expect(ModePresentationNotices.notices(for: presentation, modes: modes, mode: .source, locale: english) == expected)
        modes = SafePreviewModes(presentation, locale: english)
        modes.files = nil
        #expect(ModePresentationNotices.notices(for: presentation, modes: modes, mode: .source, locale: english) == expected)
        modes = SafePreviewModes(presentation, locale: english)
        modes.files = .init(columns: ["path"], rows: [["safe.txt"]], truncation: [.partialListing, .rows], origin: .listing)
        #expect(ModePresentationNotices.notices(for: presentation, modes: modes, mode: .files, locale: english)
            == expected + [.init(kind: .limit, text: "Showing the first 1 row.")])
    }

    @Test func byteReadAndColumnCapsShareTheBottomStripWithoutDuplicatingTheByteLimit() throws {
        let host = InteractionHarness(width: 700, height: 500)
        defer { host.release() }
        let presentation = csv(wideCSV, truncatedSourceBytes: 3_000_000)
        host.view.display(.ready(presentation), locale: english)
        try select(.table, in: host.view)
        host.view.layoutSubtreeIfNeeded()
        let bytes = try #require(PresentationNotices.notices(for: presentation, locale: english).first { $0.kind == .limit })
        let caps = PreviewStrings.text(.previewTableLimitCaps)
        #expect(host.view.limitsLabel.stringValue == bytes.text + "\n" + caps)
        #expect(occurrences(bytes.text, in: host.view.displayedStatus) == 1)
        #expect(occurrences(caps, in: host.view.displayedStatus) == 1)
        #expect(!host.view.statusLabel.stringValue.contains(bytes.text) && !host.view.statusLabel.stringValue.contains(caps))
        let pane = try visibleTable(in: host.view)
        #expect(!descendants(of: NSTextField.self, in: pane).contains { $0.stringValue == caps || $0.stringValue.contains("beyond the table limits") })
        #expect(pane.frame.minY >= host.view.limitsLabel.frame.maxY - 1)
        try select(.source, in: host.view)
        #expect(host.view.limitsLabel.stringValue == bytes.text)
        try select(.table, in: host.view)
        #expect(host.view.limitsLabel.stringValue == bytes.text + "\n" + caps)
    }

    @Test func filteringSortingAndCopyingKeepTheReadBatchCountTruthful() throws {
        let host = InteractionHarness(width: 700, height: 500)
        defer { host.release() }
        let total = SafeDelimitedTable.maximumRows + 3
        let text = "id,name\n" + (0..<total).map { "\($0),name-\($0)" }.joined(separator: "\n") + "\n"
        let presentation = csv(text, facts: .init([.grid(rows: total, columns: 2, rowsAreLowerBound: false)]))
        host.view.display(.ready(presentation), locale: english)
        try select(.table, in: host.view)
        let pane = try visibleTable(in: host.view)
        let expected = "Showing the first 20,000 rows of 20,003."
        #expect(host.view.limitsLabel.stringValue == expected)
        pane.tableView.sortDescriptors = [NSSortDescriptor(key: "0", ascending: false)]
        pane.tableView(pane.tableView, sortDescriptorsDidChange: [])
        pane.filterField.stringValue = "name-19999"
        let action = try #require(pane.filterField.action)
        #expect(pane.filterField.sendAction(action, to: pane.filterField.target))
        #expect(pane.tableView.numberOfRows == 1)
        let filtered = PreviewStrings.format(.listingFilterStatus, arguments: [Int64(1), Int64(20_000)], locale: english)
        #expect(descendants(of: NSTextField.self, in: pane).contains { !$0.isHidden && $0.stringValue == filtered })
        #expect(pane.tableView.accessibilityLabel() == PreviewStrings.format(
            .previewTableAccessibilityLabel, arguments: [Int64(1), Int64(2)], locale: english))
        pane.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        pane.tableView.copy(nil)
        #expect(host.pasteboard.string(forType: .string) == "19999\tname-19999")
        #expect(host.view.limitsLabel.stringValue == expected)
        host.view.display(.ready(presentation), theme: .dark, locale: english)
        #expect(host.view.limitsLabel.stringValue == expected)
        #expect(pane.filterField.stringValue == "name-19999" && pane.tableView.numberOfRows == 1)
    }

    @Test func replacingOrClearingThePreviewReleasesEveryOldLimitSentence() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.view.display(.ready(csv(wideCSV)), locale: english)
        try select(.table, in: host.view)
        #expect(!host.view.limitsLabel.stringValue.isEmpty)
        host.view.display(.ready(plainPresentation("safe words")), locale: english)
        #expect(host.view.limitsLabel.stringValue.isEmpty && host.view.limitsLabel.isHidden)
        host.view.display(.ready(listing(partial: true)), locale: english)
        #expect(!host.view.limitsLabel.stringValue.isEmpty)
        host.view.display(.cancelled, locale: english)
        #expect(host.view.limitsLabel.stringValue.isEmpty && host.view.limitsLabel.isHidden)
        host.view.display(.ready(csv(wideCSV)), locale: english)
        host.view.display(.unavailable(.malformedDocument), locale: english)
        #expect(host.view.limitsLabel.stringValue.isEmpty && host.view.limitsLabel.isHidden)
    }

    private func limits(_ presentation: TextPresentation, table: SafeTable, locale: Locale? = nil) -> [PresentationNotice] {
        let locale = locale ?? english
        var modes = SafePreviewModes(presentation, locale: locale)
        modes.table = table
        return ModePresentationNotices.notices(for: presentation, modes: modes, mode: .table, locale: locale)
    }

    private func csv(_ text: String, facts: PresentationFacts = .none,
                     truncatedSourceBytes: Int? = nil, origin: TextOrigin = .source,
                     format: FormatID = .csv, syntax: TextSyntax = .commaSeparated) -> TextPresentation {
        .init(formatID: format, text: text, lineCount: text.components(separatedBy: "\n").count,
            byteCount: text.utf8.count, encoding: .utf8, redactionCount: 0, syntax: syntax,
            truncatedSourceBytes: truncatedSourceBytes, origin: origin, facts: facts)
    }

    private var wideCSV: String {
        (1...70).map { "c\($0)" }.joined(separator: ",") + "\n"
        + (1...70).map(String.init).joined(separator: ",") + "\n"
    }

    private func listing(partial: Bool) -> TextPresentation {
        let json = #"{"partial":\#(partial),"entries":[{"path":"safe.txt","type":"file","bytes":1}]}"#
        return plainPresentation(json, format: .zip, syntax: .json)
    }

    private func visibleTable(in view: NativePreviewView) throws -> NativeTablePreviewView {
        try #require(descendants(of: NativeTablePreviewView.self, in: view).first { !$0.isHidden })
    }

    private func select(_ mode: NativePreviewMode, in view: NativePreviewView) throws {
        let control = view.modeControl
        let label = PreviewStrings.text(mode.title)
        let index = try #require((0..<control.segmentCount).first { control.label(forSegment: $0) == label })
        control.selectedSegment = index
        #expect(control.sendAction(control.action, to: control.target))
    }

    private func occurrences(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }
}
