import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q155 derived mode native copy services", .serialized)
@MainActor
struct Q155DerivedModeCopyPolicyTests {
    private let tags = "\u{E0061}\u{E0062}\u{E007F}"
    private let flag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
    private let locale = Locale(identifier: "en_US")

    private func harness() -> (InteractionHarness, ManualChromeScheduler) {
        let host = InteractionHarness()
        let scheduler = ManualChromeScheduler()
        host.view.chromeScheduler = scheduler
        return (host, scheduler)
    }

    private func presentation(_ mode: NativePreviewMode, text: String, findsTags: Bool) -> TextPresentation {
        let source: String
        let format: FormatID
        let syntax: TextSyntax
        if mode == .rows {
            source = "{\"dataFormat\":\"Parquet\",\"rowSample\":{\"columnNames\":[\"value\"],\"rows\":[[\"" + text + "\"]]}}"
            format = .parquet; syntax = .json
        } else {
            source = "@book{Q155Safe,title={" + text + "},author={Reader, Alex},year={2026}}"
            format = .bibtex; syntax = .bibtex
        }
        return TextPresentation(formatID: format, text: source, lineCount: 1, byteCount: source.utf8.count,
            encoding: .utf8, redactionCount: 0, syntax: syntax,
            findings: findsTags ? [.init(kind: .hiddenUnicodeTags, count: 1)] : [])
    }
    private func select(_ mode: NativePreviewMode, in host: InteractionHarness) throws -> NSView {
        let index = try #require(host.view.displayedModes.firstIndex(of: mode))
        #expect(host.view.selectMode(number: index + 1))
        return try #require(host.view.contentView(for: mode))
    }
    private func nativeText(in references: MarkupReferencesView) throws -> PreviewTextView {
        let base: NSTextView = references.textView
        return try #require(base as? PreviewTextView)
    }
    private func assertCopy(_ host: InteractionHarness, expected: String, gated: Bool,
                            nativeControl: NSPasteboard? = nil) throws {
        #expect(Array((try #require(host.pasteboard.string(forType: .string))).utf16) == Array(expected.utf16))
        let representations = try ConcealmentSurfaceSupport.pasteboardStrings(host.pasteboard)
        #expect(!representations.isEmpty)
        let types = try #require(host.pasteboard.types)
        for type in types {
            let representation = try ConcealmentSurfaceSupport.pasteboardRepresentation(host.pasteboard, type: type)
            if let nativeControl {
                let control = try ConcealmentSurfaceSupport.pasteboardRepresentation(nativeControl, type: type)
                // AppKit normalizes some rich/derived flavors (RTF and external UTF-16 on this host).
                // The primary .string stays exact; every other flavor must match an independent native writer.
                #expect(representation.string == expected, "\(type.rawValue): canonically equivalent safe text")
                #expect(Array(representation.string.utf16) == Array(control.string.utf16), "\(type.rawValue): native AppKit code units")
            } else {
                #expect(Array(representation.string.utf16) == Array(expected.utf16), "\(type.rawValue): exact displayed UTF-16")
            }
            #expect(ConcealmentSurfaceSupport.containsExact(flag, in: representation.string))
        }
        if gated {
            #expect(representations.allSatisfy { !ConcealmentSurfaceSupport.containsExact(tags, in: $0) })
        }
        #expect(ConcealmentSurfaceSupport.containsExact(flag, in: expected))
    }

    private func assertConfirmation(_ host: InteractionHarness, scheduler: ManualChromeScheduler,
                                    key: PreviewStrings.Key) {
        let message = PreviewStrings.text(key)
        #expect(host.announcements.texts == [message])
        #expect(!host.view.chip.isHidden && host.view.chip.text == message && host.view.chip.spokenText == message)
        #expect(scheduler.waiting.count == 1 && scheduler.waiting.first?.delay == PreviewChrome.chipDuration)
        scheduler.runWaiting()
        #expect(host.view.chip.isHidden && host.view.chip.text.isEmpty)
        #expect(host.announcements.texts == [message])
    }

    @Test func rowsFacadeAdoptsLivePolicyBoardAndOneNativeCopyConfirmation() throws {
        let (host, scheduler) = harness(); defer { host.release() }
        let displayed = "Q155Safe e\u{301}😀" + flag + tags
        host.view.display(.ready(presentation(.rows, text: displayed, findsTags: true)), locale: locale)
        let rows = try #require(try select(.rows, in: host) as? NativeRowsPreviewView)
        // A missing facade adoption must fail before a native copy can reach the user's clipboard.
        #expect(rows.table.pasteboard === host.pasteboard)
        try #require(rows.table.pasteboard === host.pasteboard)
        #expect(rows.table.tagCopyPolicy?() == true && rows.table.copyHandler != nil)
        host.announcements.texts.removeAll()
        let table = rows.table.tableView
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        #expect(host.window.makeFirstResponder(table))
        #expect(table.performKeyEquivalent(with: host.keyEvent("c", .command)))
        try assertCopy(host, expected: "Q155Safe e\u{301}😀" + flag, gated: true)
        assertConfirmation(host, scheduler: scheduler, key: .chipCopiedTagsRemoved)
        let cell = try #require(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTextField)
        #expect(Array(cell.stringValue.utf16) == Array(displayed.utf16))
    }

    @Test func referencesFacadeAdoptsNativeSelectionCopiesEveryRepresentationAndKeepsStorageExact() throws {
        let (host, scheduler) = harness(); defer { host.release() }
        host.view.display(.ready(presentation(.references, text: "Q155Safe e\u{301}😀" + flag + tags, findsTags: true)), locale: locale)
        let references = try #require(try select(.references, in: host) as? MarkupReferencesView)
        let text = try nativeText(in: references)
        #expect(text.pasteboard === host.pasteboard)
        try #require(text.pasteboard === host.pasteboard)
        #expect(text.tagCopyPolicy?() == true && text.copyHandler != nil)
        #expect(!text.isRichText)
        host.announcements.texts.removeAll()
        let stored = Array(text.string.utf16)
        let expected = text.string.replacingOccurrences(of: tags, with: "")
        text.isRichText = true
        let attributed = text.attributedString().copy() as! NSAttributedString
        let control = NSTextView(frame: .zero)
        control.isRichText = true
        control.string = expected
        control.setSelectedRange(NSRange(location: 0, length: expected.utf16.count))
        let nativeBoard = NSPasteboard(name: NSPasteboard.Name("q155-native-control-\(UUID().uuidString)"))
        defer { nativeBoard.releaseGlobally() }
        text.setSelectedRange(NSRange(location: 0, length: stored.count))
        #expect(control.writeSelection(to: nativeBoard, types: text.writablePasteboardTypes))
        text.copy(nil)
        #expect(host.pasteboard.types == nativeBoard.types)
        try assertCopy(host, expected: expected, gated: true, nativeControl: nativeBoard)
        #expect(host.pasteboard.types?.contains(.rtf) == true)
        assertConfirmation(host, scheduler: scheduler, key: .chipCopiedTagsRemoved)
        #expect(Array(text.string.utf16) == stored)
        #expect(text.attributedString().isEqual(to: attributed))
    }

    @Test func referencesFailedWriteAndNoSelectionDoNotAnnounce() throws {
        let (host, scheduler) = harness(); defer { host.release() }
        host.view.display(.ready(presentation(.references, text: "Q155Safe" + flag + tags, findsTags: true)), locale: locale)
        let references = try #require(try select(.references, in: host) as? MarkupReferencesView)
        let text = try nativeText(in: references)
        try #require(text.pasteboard === host.pasteboard)
        host.announcements.texts.removeAll()
        var writes = 0
        text.selectionWriter = { writer, board, _ in
            writes += 1
            #expect(board === host.pasteboard)
            #expect(ConcealmentSurfaceSupport.containsExact(flag, in: writer.string))
            #expect(!ConcealmentSurfaceSupport.containsExact(tags, in: writer.string))
            return false
        }
        text.setSelectedRange(NSRange(location: 0, length: text.string.utf16.count))
        text.copy(nil)
        #expect(writes == 1 && host.announcements.texts.isEmpty)
        #expect(host.view.chip.isHidden && scheduler.waiting.isEmpty)
        let unchanged = host.pasteboard.changeCount
        text.setSelectedRange(NSRange(location: 0, length: 0))
        text.copy(nil)
        #expect(writes == 1 && host.announcements.texts.isEmpty)
        #expect(host.view.chip.isHidden && scheduler.waiting.isEmpty)
        #expect(host.pasteboard.changeCount == unchanged)
    }

    @Test func rowsEmptySelectionDoesNotWriteOrAnnounce() throws {
        let (host, scheduler) = harness(); defer { host.release() }
        host.view.display(.ready(presentation(.rows, text: "Q155Safe" + flag + tags, findsTags: true)), locale: locale)
        let rows = try #require(try select(.rows, in: host) as? NativeRowsPreviewView)
        try #require(rows.table.pasteboard === host.pasteboard)
        host.announcements.texts.removeAll()
        #expect(host.pasteboard.setString("prior private clipboard", forType: .string))
        let before = host.pasteboard.changeCount
        rows.table.tableView.deselectAll(nil)
        rows.table.tableView.copy(nil)
        #expect(host.pasteboard.changeCount == before && host.announcements.texts.isEmpty)
        #expect(host.view.chip.isHidden && scheduler.waiting.isEmpty)
    }

    @Test func rowsFailedWriterDoesNotAnnounceOrMutateItsDisplayedCell() throws {
        let (host, scheduler) = harness(); defer { host.release() }
        let displayed = "Q155Safe" + flag + tags
        host.view.display(.ready(presentation(.rows, text: displayed, findsTags: true)), locale: locale)
        let rows = try #require(try select(.rows, in: host) as? NativeRowsPreviewView)
        try #require(rows.table.pasteboard === host.pasteboard)
        host.announcements.texts.removeAll()
        let table = rows.table.tableView
        var writes = 0
        table.selectionWriter = { value, board in
            writes += 1
            #expect(board === host.pasteboard)
            #expect(Array(value.utf16) == Array(("Q155Safe" + flag).utf16))
            return false
        }
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        table.copy(nil)
        #expect(writes == 1 && host.announcements.texts.isEmpty)
        #expect(host.view.chip.isHidden && scheduler.waiting.isEmpty)
        let cell = try #require(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTextField)
        #expect(Array(cell.stringValue.utf16) == Array(displayed.utf16))
    }

    @Test(arguments: [NativePreviewMode.rows, .references])
    func replacementRefreshesTheChildPolicyWithoutChangingDisplayedCodeUnits(mode: NativePreviewMode) throws {
        let (host, scheduler) = harness(); defer { host.release() }
        host.view.display(.ready(presentation(mode, text: "Q155Safe" + flag + tags, findsTags: true)), locale: locale)
        _ = try select(mode, in: host)
        host.view.display(.ready(presentation(mode, text: "Q155Next" + flag + tags, findsTags: false)),
                          locale: locale, resetsContentState: true)
        let content = try select(mode, in: host)
        host.announcements.texts.removeAll()
        let expected: String
        if let rows = content as? NativeRowsPreviewView {
            try #require(rows.table.pasteboard === host.pasteboard)
            #expect(rows.table.tagCopyPolicy?() == false)
            rows.table.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            rows.table.tableView.copy(nil)
            expected = "Q155Next" + flag + tags
        } else {
            let references = try #require(content as? MarkupReferencesView)
            let text = try nativeText(in: references)
            try #require(text.pasteboard === host.pasteboard)
            #expect(text.tagCopyPolicy?() == false)
            expected = text.string
            text.setSelectedRange(NSRange(location: 0, length: expected.utf16.count))
            text.copy(nil)
            #expect(Array(text.string.utf16) == Array(expected.utf16))
        }
        try assertCopy(host, expected: expected, gated: false)
        #expect(ConcealmentSurfaceSupport.containsExact(tags, in: expected))
        assertConfirmation(host, scheduler: scheduler, key: .chipCopied)
    }
}
