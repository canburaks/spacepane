import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// What a view said or reported during a test, in order.
@MainActor
private final class ModesRecorder {
    var texts: [String] = []
    var priorities: [Int] = []
    var elements: [NSView] = []
    var copies: [PreviewCopyEvent] = []
}

/// A mode view that hosts the shared table, as the Files and Rows modes do.
@MainActor
private final class ModesTableHost: NSView, SafeModeContentView, PreviewHostsTable {
    var navigate: ((NativePreviewMode, NSRange) -> Void)?
    let table = NativeTablePreviewView(frame: .zero)

    func display(_ modes: SafePreviewModes, mode: NativePreviewMode, style: SafeModeStyle) {}
    func clear() {}
}

@MainActor
private func modesKeyEvent(_ keyCode: UInt16, typed: String, modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                                  context: nil, characters: typed, charactersIgnoringModifiers: typed, isARepeat: false,
                                  keyCode: keyCode))
}

/// What the table, outline and Contents views say aloud and report (decision 027, Q-36 and Q-37): a sort or a typed
/// filter is announced through the view's announcer, a copy goes to the hosting preview once and is spoken only when
/// there is none, and the secondary chrome ink is the palette's muted tier.
@Suite("Modes announcements and copy reports", .serialized)
@MainActor
struct ModesAnnouncementTests {
    private var palette: NativeTextPalette { NativeTextPalette(theme: .system, isDark: false, increasedContrast: false) }

    private func table(palette: NativeTextPalette? = nil) -> NativeTablePreviewView {
        let view = NativeTablePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let data = SafeTable(columns: ["name", "value"],
                             rows: [["alpha", "one"], ["beta", "two"], ["alpine", "three"]], truncation: [])
        view.display(data, typography: .init(), palette: palette ?? self.palette, syntaxStyle: .init(),
                     locale: Locale(identifier: "en"))
        return view
    }

    /// Types `text` into the table's filter field the way the field reports it: through its action.
    private func enterFilter(_ text: String, in view: NativeTablePreviewView) {
        view.filterField.stringValue = text
        _ = view.filterField.sendAction(view.filterField.action, to: view.filterField.target)
    }

    private func rowsStatus(_ shown: Int, of total: Int) -> String {
        PreviewStrings.format(.listingFilterStatus, arguments: [Int64(shown), Int64(total)], locale: Locale(identifier: "en"))
    }

    private func privatePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("modes-\(UUID().uuidString)"))
    }

    // MARK: Table

    @Test func aSortIsAnnouncedOnceAndNeverAsAFilterResult() {
        let view = table()
        let spoken = ModesRecorder()
        view.announcer?.handler = { spoken.texts.append($0) }
        view.sortRows(column: 0, ascending: false)
        let descending = PreviewStrings.format(.listingSortAnnouncement,
                                               arguments: ["name", PreviewStrings.text(.listingSortDescending)],
                                               locale: Locale(identifier: "en"))
        #expect(spoken.texts == [descending])
        view.sortRows(column: 1, ascending: true)
        #expect(spoken.texts.count == 2)
        // With a filter active a sort still says only its own result.
        enterFilter("al", in: view)
        spoken.texts = []
        view.sortRows(column: 0, ascending: true)
        #expect(spoken.texts.count == 1)
        #expect(spoken.texts[0].contains("name"))
    }

    @Test func typingInTheFilterAnnouncesHowManyRowsRemainZeroIncludedAndNothingElseDoes() {
        let view = table()
        let spoken = ModesRecorder()
        view.announcer?.notificationHandler = { element, _, payload in
            spoken.elements.append(element)
            spoken.texts.append(payload[.announcement] as? String ?? "")
            spoken.priorities.append(payload[.priority] as? Int ?? -1)
        }
        enterFilter("al", in: view)
        enterFilter("alph", in: view)
        enterFilter("zzz", in: view)
        #expect(spoken.texts == [rowsStatus(2, of: 3), rowsStatus(1, of: 3), rowsStatus(0, of: 3)])
        // A result that updates while the user is typing queues behind the characters being echoed.
        #expect(spoken.priorities == Array(repeating: NSAccessibilityPriorityLevel.medium.rawValue, count: 3))
        #expect(spoken.elements.allSatisfy { $0 === view.tableView })
        // Clearing the filter brings every row back and says nothing; a change made in code says nothing either.
        enterFilter("", in: view)
        view.setFilter("be")
        #expect(spoken.texts.count == 3)
    }

    @Test func aTableCopyIsReportedOnceToTheHostAndSpokenOnlyWithoutOne() {
        let view = table()
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        view.tableView.pasteboard = pasteboard
        let spoken = ModesRecorder()
        view.announcer?.handler = { spoken.texts.append($0) }
        // Nothing selected: nothing is written, reported or said.
        view.tableView.copy(nil)
        #expect(pasteboard.string(forType: .string) == nil)
        #expect(spoken.texts.isEmpty)
        let rows: IndexSet = [0, 2]
        view.tableView.selectRowIndexes(rows, byExtendingSelection: false)
        // With no host the view says so itself.
        view.tableView.copy(nil)
        #expect(pasteboard.string(forType: .string) == "alpha\tone\nalpine\tthree")
        #expect(spoken.texts == [PreviewStrings.text(.chipCopied)])
        // With a host the copy is reported once, with its row count, and never spoken here.
        spoken.texts = []
        view.copyHandler = { spoken.copies.append($0) }
        view.tableView.copy(nil)
        #expect(spoken.copies == [.rows(2)])
        #expect(spoken.texts.isEmpty)
    }

    // MARK: Outline

    private func outlineFixture() -> NativeOutlinePreviewView {
        let view = NativeOutlinePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let nodes = [SafeOutlineNode(id: 0, name: "alpha", value: "one"), SafeOutlineNode(id: 1, name: "beta", value: "two")]
        view.display(nodes, typography: .init(), palette: palette, syntaxStyle: .init(), locale: Locale(identifier: "en"))
        return view
    }

    @Test func anOutlineCopyIsReportedWithItsKind() {
        let view = outlineFixture()
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        view.pasteboard = pasteboard
        let spoken = ModesRecorder()
        view.announcer?.handler = { spoken.texts.append($0) }
        // No host: the copy is spoken by the view.
        #expect(view.perform(.value, rows: [0, 1]))
        #expect(pasteboard.string(forType: .string) == "one\ntwo")
        #expect(spoken.texts == [PreviewStrings.text(.chipCopied)])
        // A host hears each copy once, and a path is a path.
        spoken.texts = []
        view.copyHandler = { spoken.copies.append($0) }
        #expect(view.perform(.value, rows: [0, 1]))
        #expect(view.perform(.key, rows: [1]))
        #expect(view.perform(.path, rows: [0]))
        #expect(spoken.copies == [.rows(2), .rows(1), .path])
        #expect(spoken.texts.isEmpty)
        // Rows that do not exist copy nothing and report nothing.
        #expect(!view.perform(.value, rows: [9]))
        #expect(spoken.copies.count == 3)
    }

    @Test func commandCInAnOutlineReportsTheRowsItCopied() throws {
        let view = outlineFixture()
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        view.pasteboard = pasteboard
        let spoken = ModesRecorder()
        view.copyHandler = { spoken.copies.append($0) }
        let outline = try #require(view.documentView as? NSOutlineView)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
        defer { withExtendedLifetime(window) {} }
        window.contentView = view
        window.makeFirstResponder(outline)
        outline.selectRowIndexes([0, 1], byExtendingSelection: false)
        #expect(outline.performKeyEquivalent(with: try modesKeyEvent(PreviewKeyCode.ansiC, typed: "c", modifiers: .command)))
        #expect(spoken.copies == [.rows(2)])
        #expect(pasteboard.string(forType: .string) == "alpha\tone\nbeta\ttwo")
    }

    // MARK: Contents

    @Test func aContentsCopyIsReportedToTheHostAndSpokenWithoutOne() throws {
        let view = MarkupContentsView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let markdown = "# First\n\ntext\n\n## Second"
        let presentation = TextPresentation(formatID: .markdown, text: markdown, lineCount: 5, byteCount: markdown.utf8.count,
                                            encoding: .utf8, redactionCount: 0, syntax: .markdown)
        view.display(SafePreviewModes(presentation, locale: Locale(identifier: "en")), mode: .contents,
                     style: SafeModeStyle(typography: .init(), palette: palette, syntaxStyle: .init(),
                                          locale: Locale(identifier: "en")))
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        view.pasteboard = pasteboard
        let spoken = ModesRecorder()
        view.announcer?.handler = { spoken.texts.append($0) }
        view.tableView.copy(nil)
        #expect(pasteboard.string(forType: .string) == "First")
        #expect(spoken.texts == [PreviewStrings.text(.chipCopied)])
        spoken.texts = []
        view.copyHandler = { spoken.copies.append($0) }
        view.tableView.copy(nil)
        #expect(spoken.copies == [.rows(1)])
        #expect(spoken.texts.isEmpty)
    }

    // MARK: Injection

    @Test func theViewsTakeThePreviewsAnnouncerAndAHostedTableForwardsIt() {
        let announcer = PreviewAnnouncer()
        let host = ModesTableHost(frame: .zero)
        host.announcer = announcer
        #expect(host.table.announcer === announcer)
        #expect(host.announcer === announcer)
        var heard: [PreviewCopyEvent] = []
        host.copyHandler = { heard.append($0) }
        host.table.copyHandler?(.path)
        #expect(heard == [.path])
        let contents = MarkupContentsView(frame: .zero)
        contents.announcer = announcer
        #expect(contents.tableView.announcer === announcer)
        let outline = NativeOutlinePreviewView(frame: .zero)
        outline.announcer = announcer
        #expect(outline.announcer === announcer)
        let pages = NativeImagePagesView(frame: .zero)
        pages.announcer = announcer
        #expect(pages.announcer === announcer)
        pages.clear()
        // Every one of them is a view the preview can hand its announcer to without knowing which it is.
        let hosted: [any PreviewAnnouncing] = [host, contents, outline, pages, table()]
        #expect(hosted.count == 5)
    }

    // MARK: Ink

    @Test func theFilterCountsAreDrawnInThePalettesMutedInk() throws {
        for theme in [PreviewTheme.light, PreviewTheme.dark] {
            let scheme = NativeTextPalette(theme: theme, isDark: theme == .dark, increasedContrast: false)
            let bar = OutlineFilterBar(frame: NSRect(x: 0, y: 0, width: 400, height: 30))
            bar.apply(palette: scheme)
            let count = try #require(descendants(of: NSTextField.self, in: bar).first { !($0 is NSSearchField) })
            #expect(count.textColor == scheme.muted, "outline count, \(theme)")
            let view = table(palette: scheme)
            enterFilter("al", in: view)
            let status = try #require(descendants(of: NSTextField.self, in: view).first { $0.stringValue == rowsStatus(2, of: 3) })
            #expect(status.textColor == scheme.muted, "table count, \(theme)")
        }
    }
}
