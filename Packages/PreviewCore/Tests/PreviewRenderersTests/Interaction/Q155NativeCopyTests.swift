import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@Suite("Q155 actual native clipboard hygiene", .serialized)
@MainActor
struct Q155NativeCopyTests {
    private let tags = "\u{E0061}\u{E0062}\u{E007F}"
    private let flag = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
    private let english = Locale(identifier: "en")

    @Test func actualSelectionCopySanitizesEveryNativeRepresentationWithoutChangingStorage() throws {
        let board = privateBoard()
        defer { board.releaseGlobally() }
        let view = PreviewTextView.makeTextKit1()
        view.pasteboard = board
        view.tagCopyPolicy = { true }
        view.isRichText = true
        let original = NSAttributedString(string: "safe " + tags + " e\u{301}", attributes: [.font: NSFont.boldSystemFont(ofSize: 17)])
        view.textStorage?.setAttributedString(original)
        view.setSelectedRange(NSRange(location: 0, length: original.length))
        let selection = view.selectedRanges
        let snapshot = view.attributedString().copy() as! NSAttributedString
        var events: [PreviewCopyEvent] = []
        view.copyHandler = { events.append($0) }
        view.copy(nil)
        #expect(Array((board.string(forType: .string) ?? "").utf16) == Array("safe  e\u{301}".utf16))
        #expect(events == [.text.removingTags(3)])
        #expect(view.textStorage?.isEqual(to: snapshot) == true)
        #expect(view.selectedRanges == selection)
        let rich = try #require(board.data(forType: .rtf))
        let decoded = try NSAttributedString(data: rich, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        #expect(decoded.string == "safe  e\u{301}")
        #expect((decoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        // Native readback checks every representation the view advertised, including AppKit's multiple-selection type.
        for type in board.types ?? [] {
            let receiver = NSTextView(frame: .zero)
            if receiver.readSelection(from: board, type: type) {
                #expect(!receiver.string.unicodeScalars.contains { (0xE0000...0xE007F).contains($0.value) })
            }
        }
    }

    @Test func multipleSelectionsUseNativeJoinsAndKeepPartialValidFlags() throws {
        let original = "😀" + flag + " gap " + tags + " e\u{301}"
        let sanitized = "😀" + flag + " gap  e\u{301}"
        let view = PreviewTextView.makeTextKit1()
        view.isRichText = true
        view.string = original
        view.tagCopyPolicy = { true }
        let requestedSelections = [NSValue(range: NSRange(location: 6, length: 10)), NSValue(range: NSRange(location: 21, length: 9))]
        view.selectedRanges = requestedSelections
        let selections = view.selectedRanges
        let board = privateBoard(), nativeBoard = privateBoard()
        defer { board.releaseGlobally(); nativeBoard.releaseGlobally() }
        view.pasteboard = board
        var events: [PreviewCopyEvent] = []
        view.copyHandler = { events.append($0) }
        view.copy(nil)
        let native = NSTextView(frame: .zero)
        native.isRichText = true
        native.string = sanitized
        native.selectedRanges = selections.map { selected in
            let range = selected.rangeValue
            func mapped(_ offset: Int) -> Int { offset - max(0, min(offset, 27) - 21) }
            return NSValue(range: NSRange(location: mapped(range.location), length: mapped(range.location + range.length) - mapped(range.location)))
        }
        #expect(native.writeSelection(to: nativeBoard, types: native.writablePasteboardTypes))
        #expect(board.types == nativeBoard.types)
        #expect(Array((board.string(forType: .string) ?? "").utf16) == Array((nativeBoard.string(forType: .string) ?? "").utf16))
        #expect(events == [.text.removingTags(3)])
        #expect(view.selectedRanges == selections && Array(view.string.utf16) == Array(original.utf16))
    }

    @Test(arguments: [false, true]) func richCopyCannotRetainUnsafeTagsInDocumentSuppliedAttributes(useURL: Bool) throws {
        let board = privateBoard()
        defer { board.releaseGlobally() }
        let view = PreviewTextView.makeTextKit1()
        view.pasteboard = board
        view.tagCopyPolicy = { true }
        view.isRichText = true
        let link = "https://example.test/" + tags
        let linkValue: Any = useURL ? URL(string: link)! : link
        view.textStorage?.setAttributedString(NSAttributedString(string: "•••• " + tags, attributes: [
            .font: NSFont.boldSystemFont(ofSize: 17), .link: linkValue,
            .toolTip: "inert label " + tags]))
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        let snapshot = view.attributedString().copy() as! NSAttributedString
        view.copy(nil)
        let data = try #require(board.data(forType: .rtf))
        let decoded = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        #expect(Array(decoded.string.utf16) == Array("•••• ".utf16))
        #expect(decoded.attribute(.link, at: 0, effectiveRange: nil) == nil)
        for type in [NSPasteboard.PasteboardType.rtf, .html] {
            if let representation = board.data(forType: type), let serialized = String(data: representation, encoding: .utf8) {
                #expect(!serialized.lowercased().contains("%f3%a0%81"))
            }
        }
        #expect(decoded.attribute(.toolTip, at: 0, effectiveRange: nil) == nil)
        #expect((decoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(view.textStorage?.isEqual(to: snapshot) == true)
    }

    @Test func falseWriterAndEmptySelectionNeverReportSuccessOrTouchTheGeneralClipboard() {
        let board = privateBoard()
        defer { board.releaseGlobally() }
        let view = PreviewTextView.makeTextKit1()
        view.pasteboard = board
        view.tagCopyPolicy = { true }
        view.string = "safe" + tags
        var events: [PreviewCopyEvent] = []
        var writes = 0
        view.copyHandler = { events.append($0) }
        view.selectionWriter = { writer, target, _ in
            writes += 1
            #expect(target === board)
            #expect(writer.string == "safe")
            return false
        }
        board.setString("previous", forType: .string)
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.copy(nil)
        #expect(board.string(forType: .string) == "previous" && writes == 0)
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        view.copy(nil)
        #expect(events.isEmpty && writes == 1)
    }

    @Test func selectionContainingOnlyUnsafeTagsReplacesPriorClipboardWithEmptyText() {
        let board = privateBoard()
        defer { board.releaseGlobally() }
        let view = PreviewTextView.makeTextKit1()
        view.pasteboard = board
        view.tagCopyPolicy = { true }
        // AppKit expands a run attached to preceding whitespace to that grapheme. A tags-only document gives
        // a genuinely empty sanitized selection, without asking the sanitizer to remove ordinary whitespace.
        view.string = tags
        view.setSelectedRange(NSRange(location: 0, length: 6))
        var events: [PreviewCopyEvent] = []
        view.copyHandler = { events.append($0) }
        board.setString("previous", forType: .string)
        view.copy(nil)
        #expect(board.string(forType: .string) == "")
        #expect(events == [.text.removingTags(3)])
        #expect(Array(view.string.utf16) == Array(tags.utf16))
    }

    @Test func structuredNativeRespondersSanitizeActualRowsAndReportOneCountedEvent() {
        let board = privateBoard()
        defer { board.releaseGlobally() }
        let table = NativeTablePreviewView(frame: .zero)
        let tree = NativeListingTreeView(frame: .zero)
        let contents = MarkupContentsView(frame: .zero)
        let style = SafeModeStyle(typography: .init(), palette: .init(theme: .system, isDark: false, increasedContrast: false),
                                  syntaxStyle: .init(), locale: english)
        table.display(SafeTable(columns: ["first", "second"], rows: [["\u{1F3F4}", tags], [flag + tags, ""]], truncation: []),
                      typography: .init(), palette: style.palette, syntaxStyle: .init(), locale: english)
        table.tableView.selectRowIndexes(IndexSet([0, 1]), byExtendingSelection: false)
        let listing = "{\"listedEntries\":1,\"partial\":false,\"entries\":[{\"path\":\"" + flag + tags + "\",\"type\":\"file\",\"bytes\":1}]}"
        tree.display(SafePreviewModes(plainPresentation(listing, format: .folder, syntax: .json), locale: english), mode: .tree, style: style)
        tree.outlineView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let markdown = "# " + flag + tags
        contents.display(SafePreviewModes(plainPresentation(markdown, format: .markdown, syntax: .markdown), locale: english),
                         mode: .contents, style: style)
        contents.tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        var events: [PreviewCopyEvent] = []
        for copier in [table as NSView, tree as NSView, contents as NSView] {
            let service = copier as! any PreviewSafeCopying
            service.pasteboard = board
            service.tagCopyPolicy = { true }
            (copier as! any PreviewCopyReporting).copyHandler = { events.append($0) }
        }
        table.tableView.copy(nil)
        #expect(Array((board.string(forType: .string) ?? "").utf16) == Array(("\u{1F3F4}\t\n" + flag + "\t").utf16))
        for copy in [{ tree.outlineView.copy(nil) }, { contents.tableView.copy(nil) }] {
            copy()
            let result = board.string(forType: .string) ?? ""
            #expect(TagCopySanitizer(safeDisplayedText: result, safetyLensFoundTags: true).wholeText().removedTagScalarCount == 0)
            #expect(Array(result.utf16).starts(with: Array(flag.utf16)))
        }
        #expect(events == [.rows(2).removingTags(6), .rows(1).removingTags(3), .rows(1).removingTags(3)])
    }

    @Test func outlineKeyValuePathAndRowCopyRemoveUnsafeTagsOnlyWhenEnabled() throws {
        let board = privateBoard()
        defer { board.releaseGlobally() }
        let view = NativeOutlinePreviewView(frame: .zero)
        view.pasteboard = board
        view.tagCopyPolicy = { true }
        view.display([.init(id: 0, name: "$", value: "{…}", children: [.init(id: 1, name: "key" + tags, value: flag + tags)])],
                     typography: .init(), palette: .init(theme: .system, isDark: false, increasedContrast: false),
                     syntaxStyle: .init(), locale: english)
        var events: [PreviewCopyEvent] = []
        view.copyHandler = { events.append($0) }
        for action in OutlineRowAction.allCases {
            #expect(view.perform(action, rows: IndexSet(integer: 1)))
            let copied = try #require(board.string(forType: .string))
            #expect(TagCopySanitizer(safeDisplayedText: copied, safetyLensFoundTags: true).wholeText().removedTagScalarCount == 0)
        }
        #expect(events.map(\.removedTagScalarCount) == [3, 3, 3])
        view.tagCopyPolicy = { false }
        #expect(view.perform(.value, rows: IndexSet(integer: 1)))
        #expect(Array((board.string(forType: .string) ?? "").utf16) == Array((flag + tags).utf16))
        #expect(events.last == .rows(1))
    }

    @Test func liveHostPolicyChangesWithTheCurrentGenerationAndCopiesOnlyCurrentText() {
        let host = InteractionHarness()
        defer { host.release() }
        host.view.display(.ready(presentation("safe" + tags, findsTags: true)), locale: english)
        host.view.textView.setSelectedRange(NSRange(location: 0, length: host.view.textView.string.utf16.count))
        host.view.textView.copy(nil)
        #expect(Array((host.pasteboard.string(forType: .string) ?? "").utf16) == Array("safe".utf16))
        #expect(host.announcements.texts == [PreviewStrings.text(.chipCopiedTagsRemoved)])
        host.view.display(.ready(presentation("next" + tags, findsTags: false)), locale: english, resetsContentState: true)
        host.view.textView.setSelectedRange(NSRange(location: 0, length: host.view.textView.string.utf16.count))
        host.view.textView.copy(nil)
        #expect(Array((host.pasteboard.string(forType: .string) ?? "").utf16) == Array(("next" + tags).utf16))
        #expect(host.announcements.texts.last == PreviewStrings.text(.chipCopied))
        host.view.display(.unavailable(.missingFile), locale: english)
        host.pasteboard.clearContents()
        host.view.textView.copy(nil)
        #expect(host.pasteboard.string(forType: .string) == nil)
    }

    @Test func copyAllAndConcealedCopyUseTheFindingGateAndConfirmOnlySuccessfulWrites() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.view.concealedTextPasteboard = host.pasteboard
        host.view.display(.ready(presentation("•••• " + flag + tags, findsTags: true)), locale: english)
        #expect(host.view.copyAllSafeText())
        #expect(Array((host.pasteboard.string(forType: .string) ?? "").utf16) == Array(("•••• " + flag).utf16))
        let invisibles = try #require(host.view.displayedModes.firstIndex(of: .invisibles))
        host.view.modeControl.selectedSegment = invisibles
        #expect(host.view.modeControl.sendAction(host.view.modeControl.action, to: host.view.modeControl.target))
        host.view.copyConcealedText()
        #expect(Array((host.pasteboard.string(forType: .string) ?? "").utf16) == Array(("•••• " + flag).utf16))
        #expect(host.announcements.texts == Array(repeating: PreviewStrings.text(.chipCopiedTagsRemoved), count: 2))
        host.view.plainTextCopyWriter = { _, board in
            #expect(board === host.pasteboard)
            return false
        }
        #expect(!host.view.copyAllSafeText())
        host.view.copyConcealedText()
        #expect(host.announcements.texts.count == 2)
    }

    private func privateBoard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("q155-\(UUID().uuidString)"))
    }

    private func presentation(_ text: String, findsTags: Bool) -> TextPresentation {
        .init(formatID: .plainText, text: text, lineCount: 1, byteCount: text.utf8.count, encoding: .utf8,
              redactionCount: 1, findings: findsTags ? [.init(kind: .hiddenUnicodeTags, count: 3)] : [])
    }
}
