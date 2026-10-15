import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Owner decisions of 2026-10-15. Finder does not pass typed keys to a Quick Look extension, so a typed filter
/// there is a dead field whose keystrokes select other files: the table filter field stays hidden until asked for,
/// and a host without typed input never offers it. The profile sampling and concealed-column notes and the
/// invisibles note are not shown at all.
@Suite("Hidden table filter and removed notes", .serialized)
@MainActor
struct HiddenFilterAndNotesTests {
    private let csv = "name,count\nalpha,1\nbeta,2\ngamma,3"
    private let english = Locale(identifier: "en_US")

    private func csvTable(acceptsTypedInput: Bool = true) throws -> (InteractionHarness, NativeTablePreviewView) {
        let host = InteractionHarness()
        host.view.acceptsTypedInput = acceptsTypedInput
        host.show(plainPresentation(csv, format: .csv, syntax: .commaSeparated))
        let index = try #require(host.view.displayedModes.firstIndex(of: .table))
        #expect(host.view.selectMode(number: index + 1))
        let table = try #require(host.view.contentView(for: .table) as? NativeTablePreviewView)
        return (host, table)
    }

    @Test func theFilterFieldIsHiddenUntilAskedForAndTheSortMenuStays() throws {
        let (host, table) = try csvTable()
        defer { host.release() }
        #expect(!table.filterBar.isHidden)
        #expect(table.filterField.isHidden)
        #expect(!table.sortButton.isHidden)
        #expect(!table.searchButton.isHidden)
        #expect(table.showFilter())
        #expect(!table.filterField.isHidden)
        #expect(table.searchButton.isHidden)
    }

    @Test func theSearchButtonOpensTheFilterField() throws {
        let (host, table) = try csvTable()
        defer { host.release() }
        table.searchButton.performClick(nil)
        #expect(!table.filterField.isHidden)
        #expect(table.filterField.currentEditor() != nil)
    }

    @Test func aHostWithoutTypedInputNeverOffersTheFilter() throws {
        let (host, table) = try csvTable(acceptsTypedInput: false)
        defer { host.release() }
        #expect(table.filterField.isHidden)
        #expect(table.searchButton.isHidden)
        #expect(!table.sortButton.isHidden)
        #expect(!table.showFilter())
        #expect(table.filterField.isHidden)
        #expect(!host.press("f", .command))
        #expect(!host.view.commandAvailability.contains(.find))
        #expect(!host.view.commandAvailability.contains(.goToLine))
    }

    @Test func aHostWithoutTypedInputOffersNoTextSearchOrGoToLine() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.view.acceptsTypedInput = false
        host.show(plainPresentation("one\ntwo\n", format: .plainText, syntax: .plain))
        #expect(!host.view.commandAvailability.contains(.find))
        #expect(!host.view.commandAvailability.contains(.goToLine))
        #expect(host.view.commandAvailability.contains(.copyConcealed) || host.view.commandAvailability.contains(.copy))
    }

    @Test func aHostWithoutTypedInputShowsNoOutlineFilter() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.view.acceptsTypedInput = false
        host.show(plainPresentation(#"{"a":{"b":1}}"#, format: .json, syntax: .json))
        let index = try #require(host.view.displayedModes.firstIndex(of: .outline))
        #expect(host.view.selectMode(number: index + 1))
        #expect(host.view.accessoryBar.filterBar.isHidden)
    }

    @Test func theInvisiblesModeHasNoNote() {
        let presentation = plainPresentation("a\u{200B}b", format: .plainText, syntax: .plain)
        let notices = PreviewStatePresenter.notices(for: presentation, mode: .invisibles, hasStructureFallback: false,
                                                    markupNotices: [], profileNotices: [], hasRecords: false,
                                                    locale: english)
        #expect(notices.isEmpty)
    }

    @Test func profileNotesLeaveOutSamplingAndConcealedColumns() {
        let source = SafeTable(columns: ["a"], rows: (0..<10_010).map { [String($0)] }, truncation: [])
        let profile = LazyDataProfile(source: source, locale: english)
        #expect(profile.value.statusLines == ["Rows profiled: 10,000 of 10,010"])
        #expect(profile.value.noteLines.isEmpty)
    }
}
