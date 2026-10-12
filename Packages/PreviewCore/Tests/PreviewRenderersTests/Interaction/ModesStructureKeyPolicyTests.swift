import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// The parent of a content view under test. It records the key events the view hands on, so a test can see that
/// Space and Escape travel up the responder chain untouched.
@MainActor
private final class ModesKeyCatcher: NSView {
    private(set) var received: [UInt16] = []
    override func keyDown(with event: NSEvent) { received.append(event.keyCode) }
}

/// Spoken notices a view asked for, in order.
@MainActor
private final class ModesSpoken {
    var texts: [String] = []
}

/// A mode view that scales its own content, as a diagram canvas does.
@MainActor
private final class ModesZoomStub: NSView, SafeModeZoomable {
    var navigate: ((NativePreviewMode, NSRange) -> Void)?
    private let handles: Bool
    private(set) var received: [PreviewShortcut] = []

    init(handles: Bool) {
        self.handles = handles
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    func display(_ modes: SafePreviewModes, mode: NativePreviewMode, style: SafeModeStyle) {}
    func clear() {}

    func handleZoom(_ shortcut: PreviewShortcut) -> Bool {
        received.append(shortcut)
        return handles
    }
}

/// A mode view that is itself a responder, or is not, to pin the default keyboard focus target.
@MainActor
private final class ModesFocusStub: NSView, SafeModeContentView {
    var navigate: ((NativePreviewMode, NSRange) -> Void)?
    private let accepts: Bool

    init(accepts: Bool) {
        self.accepts = accepts
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { accepts }

    func display(_ modes: SafePreviewModes, mode: NativePreviewMode, style: SafeModeStyle) {}
    func clear() {}
}

@MainActor
private func modesKey(_ keyCode: UInt16, typed: String = "", modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
                                  context: nil, characters: typed, charactersIgnoringModifiers: typed, isARepeat: false,
                                  keyCode: keyCode))
}

/// The key policy of decision 027 (amendment 10, owner decision D9) in the views this workstream owns: Space and
/// Escape are never bound, arrows act only inside a content view that has keyboard focus, Find says that it is
/// unavailable, and the shortcuts follow the keyboard layout. Events are synthetic and every pasteboard is private.
@Suite("Modes key policy", .serialized)
@MainActor
struct ModesKeyPolicyTests {
    private struct PagesFixture {
        let view: NativeImagePagesView
        let catcher: ModesKeyCatcher
        let window: NSWindow
    }

    private struct ContentsFixture {
        let view: MarkupContentsView
        let catcher: ModesKeyCatcher
        let window: NSWindow
    }

    private var downArrow: String { String(UnicodeScalar(NSDownArrowFunctionKey)!) }

    private var palette: NativeTextPalette { NativeTextPalette(theme: .system, isDark: false, increasedContrast: false) }

    private func style() -> SafeModeStyle {
        SafeModeStyle(typography: .init(), palette: palette, syntaxStyle: .init(), locale: Locale(identifier: "en"))
    }

    /// A page column inside a window, under a parent that records the keys handed up to it. Decoding never
    /// produces a picture, so no test waits on it.
    private func pages(count: Int = 60) -> PagesFixture {
        let view = NativeImagePagesView(frame: NSRect(x: 0, y: 0, width: 600, height: 400),
                                        scheduler: ImagePageScheduler(maximumConcurrent: 1, decode: { _, _ in nil }))
        let catcher = ModesKeyCatcher(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        catcher.addSubview(view)
        let window = NSWindow(contentRect: catcher.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = catcher
        let images = (0..<count).map { PreviewImage(data: Data("page-\($0)".utf8), pixelWidth: 100, pixelHeight: 140, role: .page) }
        let presentation = TextPresentation(formatID: .comicBook, text: "{}", lineCount: 1, byteCount: 2, encoding: .utf8,
                                            redactionCount: 0, syntax: .json, images: images)
        view.display(SafePreviewModes(presentation, locale: Locale(identifier: "en")), mode: .pages, style: style())
        view.layoutSubtreeIfNeeded()
        return PagesFixture(view: view, catcher: catcher, window: window)
    }

    /// The Contents list of a four-heading document inside a window.
    private func contents() -> ContentsFixture {
        let view = MarkupContentsView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let catcher = ModesKeyCatcher(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        catcher.addSubview(view)
        let window = NSWindow(contentRect: catcher.frame, styleMask: [.titled], backing: .buffered, defer: true)
        window.contentView = catcher
        let markdown = "# First\n\ntext\n\n## Second\n\n### Third\n\n# Fourth"
        let presentation = TextPresentation(formatID: .markdown, text: markdown, lineCount: 9, byteCount: markdown.utf8.count,
                                            encoding: .utf8, redactionCount: 0, syntax: .markdown)
        view.display(SafePreviewModes(presentation, locale: Locale(identifier: "en")), mode: .contents, style: style())
        return ContentsFixture(view: view, catcher: catcher, window: window)
    }

    private func privatePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("modes-\(UUID().uuidString)"))
    }

    // MARK: Space and Escape

    @Test func returnAndEnterShowTheHeadingButSpaceNeverDoes() throws {
        let fixture = contents()
        defer { withExtendedLifetime(fixture) {} }
        let view = fixture.view
        var shown: [Int] = []
        view.navigate = { _, range in shown.append(range.location) }
        view.tableView.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        view.tableView.keyDown(with: try modesKey(PreviewKeyCode.returnKey, typed: "\r"))
        view.tableView.keyDown(with: try modesKey(PreviewKeyCode.keypadEnter, typed: "\u{3}"))
        #expect(shown.count == 2)
        #expect(Set(shown).count == 1)
        // Space does not show the heading, with or without Shift, and the arrows only move the selection.
        view.tableView.keyDown(with: try modesKey(PreviewKeyCode.space, typed: " "))
        view.tableView.keyDown(with: try modesKey(PreviewKeyCode.space, typed: " ", modifiers: .shift))
        view.tableView.keyDown(with: try modesKey(125, typed: downArrow))
        #expect(shown.count == 2)
    }

    @Test func theContentsListHandsSpaceAndEscapeOnToTheNextResponder() throws {
        // A bare list directly under a spy: its next responder is the spy, so no other view in the chain can take
        // the key.
        let catcher = ModesKeyCatcher(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let table = ContentsTableView(frame: catcher.bounds)
        catcher.addSubview(table)
        var activations = 0
        table.onActivate = { _ in activations += 1 }
        #expect(table.nextResponder === catcher)
        table.keyDown(with: try modesKey(PreviewKeyCode.space, typed: " "))
        table.keyDown(with: try modesKey(PreviewKeyCode.escape, typed: "\u{1B}"))
        table.keyDown(with: try modesKey(PreviewKeyCode.space, typed: " ", modifiers: .shift))
        #expect(catcher.received == [PreviewKeyCode.space, PreviewKeyCode.escape, PreviewKeyCode.space])
        #expect(activations == 0)
    }

    @Test func spaceIsHandedOnAndNeverScrollsThePages() throws {
        let fixture = pages()
        defer { withExtendedLifetime(fixture) {} }
        let view = fixture.view
        func top() -> CGFloat { view.contentView.documentVisibleRect.minY }
        #expect(view.takeKeyboardFocus())
        let space = try modesKey(PreviewKeyCode.space, typed: " ")
        let shiftSpace = try modesKey(PreviewKeyCode.space, typed: " ", modifiers: .shift)
        #expect(!view.handleNavigationKey(space))
        #expect(!view.handleNavigationKey(shiftSpace))
        #expect(!view.performKeyEquivalent(with: space))
        view.keyDown(with: space)
        view.keyDown(with: shiftSpace)
        #expect(top() == 0)
        #expect(fixture.catcher.received == [PreviewKeyCode.space, PreviewKeyCode.space])
        view.keyDown(with: try modesKey(PreviewKeyCode.escape, typed: "\u{1B}"))
        #expect(fixture.catcher.received.last == PreviewKeyCode.escape)
        view.clear()
    }

    // MARK: Arrows and focus

    @Test func theArrowsAndPagingKeysActOnlyWhileThePagesHaveFocus() throws {
        let fixture = pages()
        defer { withExtendedLifetime(fixture) {} }
        let view = fixture.view
        func top() -> CGFloat { view.contentView.documentVisibleRect.minY }
        let down = try modesKey(125, typed: downArrow)
        let commandDown = try modesKey(125, typed: downArrow, modifiers: .command)
        // A key-equivalent pass without focus leaves every key for others.
        #expect(!view.hasKeyboardFocus)
        #expect(!view.performKeyEquivalent(with: down))
        #expect(!view.performKeyEquivalent(with: commandDown))
        #expect(top() == 0)
        #expect(view.takeKeyboardFocus())
        #expect(view.hasKeyboardFocus)
        #expect(fixture.window.firstResponder === view.keyboardFocusTarget)
        view.keyDown(with: down)
        #expect(top() == 40)
        view.keyDown(with: try modesKey(126))
        #expect(top() == 0)
        #expect(view.performKeyEquivalent(with: commandDown))
        #expect(top() > 0)
        #expect(view.handleNavigationKey(try modesKey(115)))
        #expect(top() == 0)
        let page = view.contentView.bounds.height * 0.9
        #expect(view.handleNavigationKey(try modesKey(121)))
        #expect(abs(top() - page) < 1)
        #expect(fixture.catcher.received.isEmpty)
        view.clear()
    }

    @Test func leftAndRightArrowsTurnPagesAndNothingElseHandlesLetters() throws {
        let fixture = pages(count: 10)
        defer { withExtendedLifetime(fixture) {} }
        let view = fixture.view
        #expect(view.handleNavigationKey(try modesKey(124)))
        #expect(view.topPageIndex == 1)
        #expect(view.handleNavigationKey(try modesKey(123)))
        #expect(view.topPageIndex == 0)
        #expect(!view.handleNavigationKey(try modesKey(PreviewKeyCode.ansiL, typed: "l", modifiers: .command)))
        view.clear()
    }

    @Test func thePageColumnTakesKeyboardFocusInItsDocumentContainerAndGivesItUp() throws {
        let fixture = pages(count: 3)
        defer { withExtendedLifetime(fixture) {} }
        let view = fixture.view
        let target = view.keyboardFocusTarget
        // Focus lives in a plain view inside the scroll view, as a table's does, so it never depends on how a scroll
        // view takes first responder status.
        #expect(target?.acceptsFirstResponder == true)
        #expect(target?.isDescendant(of: view) == true)
        #expect(!view.hasKeyboardFocus)
        #expect(view.takeKeyboardFocus())
        #expect(view.hasKeyboardFocus)
        #expect(fixture.window.firstResponder === target)
        // Focus anywhere else in the window ends it, and the arrows are Quick Look's again.
        fixture.window.makeFirstResponder(nil)
        #expect(!view.hasKeyboardFocus)
        #expect(!view.performKeyEquivalent(with: try modesKey(125, typed: downArrow, modifiers: .command)))
        view.clear()
    }

    @Test func aPageColumnOutsideAWindowTakesNoFocus() {
        let view = NativeImagePagesView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        #expect(!view.hasKeyboardFocus)
        #expect(!view.takeKeyboardFocus())
        view.clear()
    }

    @Test func theContentsListNamesItsTableAsTheFocusTarget() {
        let fixture = contents()
        defer { withExtendedLifetime(fixture) {} }
        let table = fixture.view.tableView
        #expect(fixture.view.keyboardFocusTarget === table)
        #expect(fixture.window.makeFirstResponder(fixture.view.keyboardFocusTarget))
        #expect(fixture.window.firstResponder === table)
    }

    @Test func aModeViewThatIsItselfAResponderIsItsOwnFocusTarget() {
        let responder = ModesFocusStub(accepts: true)
        #expect(responder.keyboardFocusTarget === responder)
        let container = ModesFocusStub(accepts: false)
        #expect(container.keyboardFocusTarget == nil)
    }

    // MARK: Find

    @Test func findIsAnsweredAloudInContentsOnlyWhileTheListHasFocus() throws {
        let fixture = contents()
        defer { withExtendedLifetime(fixture) {} }
        let table = fixture.view.tableView
        let spoken = ModesSpoken()
        table.announcer?.handler = { spoken.texts.append($0) }
        let find = try modesKey(PreviewKeyCode.ansiF, typed: "f", modifiers: .command)
        let findNext = try modesKey(PreviewKeyCode.ansiG, typed: "g", modifiers: .command)
        let findPrevious = try modesKey(PreviewKeyCode.ansiG, typed: "G", modifiers: [.command, .shift])
        #expect(!table.performKeyEquivalent(with: find))
        #expect(spoken.texts.isEmpty)
        fixture.window.makeFirstResponder(table)
        let expected = PreviewStrings.text(.interactionFindUnavailable)
        for event in [find, findNext, findPrevious] { #expect(table.performKeyEquivalent(with: event)) }
        #expect(spoken.texts == [expected, expected, expected])
        // A Russian keyboard's Find is the same chord, and other chords are not answered.
        #expect(table.performKeyEquivalent(with: try modesKey(PreviewKeyCode.ansiF, typed: "а", modifiers: .command)))
        #expect(spoken.texts.count == 4)
        #expect(!table.performKeyEquivalent(with: try modesKey(PreviewKeyCode.ansiL, typed: "l", modifiers: .command)))
        #expect(spoken.texts.count == 4)
    }

    @Test func findIsAnsweredAloudInPagesOnlyWhileTheyHaveFocus() throws {
        let fixture = pages(count: 3)
        defer { withExtendedLifetime(fixture) {} }
        let view = fixture.view
        let spoken = ModesSpoken()
        view.announcer?.handler = { spoken.texts.append($0) }
        let find = try modesKey(PreviewKeyCode.ansiF, typed: "f", modifiers: .command)
        let findNext = try modesKey(PreviewKeyCode.ansiG, typed: "g", modifiers: .command)
        let findPrevious = try modesKey(PreviewKeyCode.ansiG, typed: "G", modifiers: [.command, .shift])
        #expect(!view.performKeyEquivalent(with: find))
        #expect(spoken.texts.isEmpty)
        #expect(view.takeKeyboardFocus())
        let expected = PreviewStrings.text(.interactionFindUnavailable)
        for event in [find, findNext, findPrevious] { #expect(view.performKeyEquivalent(with: event)) }
        #expect(spoken.texts == [expected, expected, expected])
        #expect(!view.performKeyEquivalent(with: try modesKey(PreviewKeyCode.ansiL, typed: "l", modifiers: .command)))
        #expect(spoken.texts.count == 3)
        view.clear()
    }

    @Test func theFindHelperAnswersOnlyFindEvents() throws {
        let view = NSView(frame: .zero)
        let spoken = ModesSpoken()
        let announcer = PreviewAnnouncer()
        announcer.handler = { spoken.texts.append($0) }
        #expect(PreviewKeyPolicy.answerFindUnavailable(try modesKey(PreviewKeyCode.ansiF, typed: "f", modifiers: .command),
                                                       using: announcer, from: view))
        #expect(!PreviewKeyPolicy.answerFindUnavailable(try modesKey(PreviewKeyCode.ansiC, typed: "c", modifiers: .command),
                                                        using: announcer, from: view))
        #expect(!PreviewKeyPolicy.answerFindUnavailable(try modesKey(PreviewKeyCode.ansiF, typed: "f", modifiers: []),
                                                        using: announcer, from: view))
        #expect(spoken.texts == [PreviewStrings.text(.interactionFindUnavailable)])
        // With no announcer the key is still answered, only unspoken.
        #expect(PreviewKeyPolicy.answerFindUnavailable(try modesKey(PreviewKeyCode.ansiG, typed: "g", modifiers: .command),
                                                       using: nil, from: view))
        #expect(spoken.texts.count == 1)
    }

    // MARK: Copy on any layout

    @Test func commandCCopiesTheSelectedHeadingOnAnyLayoutWhileTheListHasFocus() throws {
        let fixture = contents()
        defer { withExtendedLifetime(fixture) {} }
        let table = fixture.view.tableView
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        fixture.view.pasteboard = pasteboard
        #expect(table.pasteboard === pasteboard)
        table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        // A Russian keyboard types a с on the C key.
        let russianC = try modesKey(PreviewKeyCode.ansiC, typed: "с", modifiers: .command)
        #expect(!table.performKeyEquivalent(with: russianC))
        #expect(pasteboard.string(forType: .string) == nil)
        fixture.window.makeFirstResponder(table)
        #expect(table.performKeyEquivalent(with: russianC))
        #expect(pasteboard.string(forType: .string) == "Second")
        pasteboard.clearContents()
        #expect(table.performKeyEquivalent(with: try modesKey(PreviewKeyCode.ansiC, typed: "c", modifiers: .command)))
        #expect(pasteboard.string(forType: .string) == "Second")
    }

    @Test func theOutlineCopiesOnCommandCWhateverTheLayoutTypesWhileItHasFocus() throws {
        let view = NativeOutlinePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        view.pasteboard = pasteboard
        let nodes = [SafeOutlineNode(id: 0, name: "alpha", value: "one"), SafeOutlineNode(id: 1, name: "beta", value: "two")]
        view.display(nodes, typography: .init(), palette: palette, syntaxStyle: .init(), locale: Locale(identifier: "en"))
        let outline = try #require(view.documentView as? NSOutlineView)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
        defer { withExtendedLifetime(window) {} }
        window.contentView = view
        outline.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let russianC = try modesKey(PreviewKeyCode.ansiC, typed: "с", modifiers: .command)
        #expect(!outline.performKeyEquivalent(with: russianC))
        #expect(pasteboard.string(forType: .string) == nil)
        window.makeFirstResponder(outline)
        #expect(outline.performKeyEquivalent(with: russianC))
        #expect(pasteboard.string(forType: .string) == "alpha\tone")
    }

    @Test func theTableCopiesAndMovesToItsFilterWhateverTheLayoutTypes() throws {
        let view = NativeTablePreviewView(frame: NSRect(x: 0, y: 0, width: 600, height: 300))
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        view.tableView.pasteboard = pasteboard
        let table = SafeTable(columns: ["name", "value"], rows: [["alpha", "one"], ["beta", "two"]], truncation: [])
        view.display(table, typography: .init(), palette: palette, syntaxStyle: .init(), locale: Locale(identifier: "en"))
        var focused = 0
        view.tableView.focusFilter = { focused += 1 }
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: true)
        defer { withExtendedLifetime(window) {} }
        window.contentView = view
        view.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let russianC = try modesKey(PreviewKeyCode.ansiC, typed: "с", modifiers: .command)
        let russianF = try modesKey(PreviewKeyCode.ansiF, typed: "а", modifiers: .command)
        #expect(!view.tableView.performKeyEquivalent(with: russianC))
        #expect(!view.tableView.performKeyEquivalent(with: russianF))
        #expect(pasteboard.string(forType: .string) == nil)
        #expect(focused == 0)
        window.makeFirstResponder(view.tableView)
        #expect(view.tableView.performKeyEquivalent(with: russianC))
        #expect(pasteboard.string(forType: .string) == "beta\ttwo")
        #expect(view.tableView.performKeyEquivalent(with: russianF))
        #expect(focused == 1)
    }

    @Test func layoutIndependentShortcutsReachThePreview() throws {
        let host = InteractionHarness()
        defer { host.release() }
        host.show(plainPresentation(numberedLines(40)))
        // French AZERTY types an a-grave on the 0 key, so Command-0 found no shortcut before the key code counted.
        #expect(host.view.performKeyEquivalent(with: try modesKey(PreviewKeyCode.numberRow[0], typed: "à", modifiers: .command)))
        // A Russian keyboard types a д on the L key: Go to Line.
        #expect(host.view.performKeyEquivalent(with: try modesKey(PreviewKeyCode.ansiL, typed: "д", modifiers: .command)))
        // A key no shortcut owns still travels on.
        #expect(!host.view.performKeyEquivalent(with: try modesKey(PreviewKeyCode.ansiL, typed: "д")))
    }

    // MARK: Zoom routing

    @Test func zoomShortcutsAreOfferedToTheVisibleModeViewFirst() {
        // A view drawn in the preview's typography takes the usual text zoom.
        let listFixture = contents()
        defer { withExtendedLifetime(listFixture) {} }
        let list = listFixture.view
        #expect(list.respondsToTextZoom)
        #expect(list.zoomDecision(for: .zoomIn) == nil)
        // The page column is pictures: no typography change and no zoom status.
        let columnFixture = pages(count: 2)
        defer { withExtendedLifetime(columnFixture) {} }
        let column = columnFixture.view
        #expect(!column.respondsToTextZoom)
        #expect(column.zoomDecision(for: .zoomIn) == false)
        column.clear()
        // A view that scales its own content decides for itself, and sees the shortcut it was offered.
        let canvas = ModesZoomStub(handles: true)
        #expect(canvas.zoomDecision(for: .zoomOut) == true)
        let refusing = ModesZoomStub(handles: false)
        #expect(refusing.zoomDecision(for: .zoomReset) == false)
        #expect(canvas.received == [.zoomOut])
        #expect(refusing.received == [.zoomReset])
    }
}
