import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Quick win 2 of the 2026-10-14 list: in a table mode Command-F opens the table's filter from anywhere in the
/// preview, exactly as it does while the table has focus. Availability advertises Command-F only where it works.
@Suite("Table filter from Command-F", .serialized)
@MainActor
struct TqInteractionFilterShortcutTests {
    private let csv = "name,count\nalpha,1\nbeta,2\ngamma,3"
    private let rows = #"{"dataFormat":"Parquet","rowSample":{"columnNames":["value"],"rows":[["alpha"],["beta"]]}}"#

    /// A preview showing `mode` of `presentation`, with the window it is in.
    private func preview(_ presentation: TextPresentation, mode: NativePreviewMode) throws -> InteractionHarness {
        let host = InteractionHarness()
        host.show(presentation)
        let index = try #require(host.view.displayedModes.firstIndex(of: mode))
        #expect(host.view.selectMode(number: index + 1))
        #expect(host.view.selectedMode == mode)
        return host
    }

    private func csvTable() throws -> InteractionHarness {
        try preview(plainPresentation(csv, format: .csv, syntax: .commaSeparated), mode: .table)
    }

    /// Whether the table's filter field is the window's text editor, which is what keyboard focus in it means.
    private func isEditing(_ field: NSSearchField, in host: InteractionHarness) -> Bool {
        field.currentEditor() != nil && host.window.firstResponder === field.currentEditor()
    }

    @Test func commandFWithFocusNowhereInThePreviewOpensAndFocusesTheTableFilter() throws {
        let host = try csvTable()
        defer { host.release() }
        let table = try #require(host.view.contentView(for: .table) as? NativeTablePreviewView)
        #expect(host.window.firstResponder === host.window)
        #expect(host.press("f", .command))
        #expect(isEditing(table.filterField, in: host))
    }

    @Test func commandFWithFocusOnAnotherControlInThePreviewOpensAndFocusesTheTableFilter() throws {
        let host = try csvTable()
        defer { host.release() }
        let table = try #require(host.view.contentView(for: .table) as? NativeTablePreviewView)
        #expect(host.window.makeFirstResponder(host.view.modeControl))
        #expect(host.press("f", .command))
        #expect(isEditing(table.filterField, in: host))
    }

    @Test func commandFWithFocusInTheTableStillFocusesTheFilter() throws {
        let host = try csvTable()
        defer { host.release() }
        let table = try #require(host.view.contentView(for: .table) as? NativeTablePreviewView)
        #expect(host.window.makeFirstResponder(table.tableView))
        #expect(host.press("f", .command))
        #expect(isEditing(table.filterField, in: host))
    }

    @Test func commandFWithFocusInsideAHostedRowsTableOpensItsFilter() throws {
        let host = try preview(plainPresentation(rows, format: .parquet, syntax: .json), mode: .rows)
        defer { host.release() }
        let rowsView = try #require(host.view.shownModeView as? NativeRowsPreviewView)
        #expect(host.window.firstResponder === host.window)
        #expect(host.press("f", .command))
        #expect(isEditing(rowsView.table.filterField, in: host))
    }

    @Test func commandFWhileFocusIsOutsideThePreviewIsNotTaken() throws {
        let host = try csvTable()
        defer { host.release() }
        let table = try #require(host.view.contentView(for: .table) as? NativeTablePreviewView)
        // A control beside the preview in the same window: the preview must leave its key equivalents alone.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let outside = NSTextField(frame: NSRect(x: 0, y: 440, width: 200, height: 24))
        host.window.contentView = container
        container.addSubview(outside)
        container.addSubview(host.view)
        #expect(host.window.makeFirstResponder(outside))
        #expect(!host.view.ownsKeyboardFocus)
        #expect(!host.press("f", .command))
        #expect(!isEditing(table.filterField, in: host))
    }

    @Test func availabilityAdvertisesFindExactlyWhereCommandFOpensAFilter() throws {
        let host = try csvTable()
        defer { host.release() }
        let availability = host.view.commandAvailability
        #expect(availability.contains(.find))
        #expect(!availability.contains(.findNext) && !availability.contains(.findPrevious))
        #expect(!availability.contains(.goToLine))
        #expect(host.press("f", .command) == availability.contains(.find))
    }

    @Test func rowsAdvertiseFindWithTheirFilterAndOpenIt() throws {
        let host = try preview(plainPresentation(rows, format: .parquet, syntax: .json), mode: .rows)
        defer { host.release() }
        #expect(host.view.commandAvailability.contains(.find))
        #expect(host.press("f", .command) == host.view.commandAvailability.contains(.find))
    }

    @Test func textModesStillSendCommandFToTheTextFinderNotToATable() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.show(plainPresentation(numberedLines(20)))
        #expect(host.textView.usesFindBar)
        #expect(host.press("f", .command))
        #expect(host.view.scrollView.isFindBarVisible)
    }
}
