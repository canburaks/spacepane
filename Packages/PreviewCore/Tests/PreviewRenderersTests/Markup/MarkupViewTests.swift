import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

@MainActor
private func style(theme: PreviewTheme = .system) -> SafeModeStyle {
    SafeModeStyle(typography: .init(), palette: NativeTextPalette(theme: theme, isDark: false, increasedContrast: false),
                  syntaxStyle: .init(), locale: Locale(identifier: "en"))
}

private func modes(_ id: FormatID, _ text: String, syntax: TextSyntax) -> SafePreviewModes {
    SafePreviewModes(TextPresentation(formatID: id, text: text, lineCount: 1, byteCount: text.utf8.count, encoding: .utf8,
                                      redactionCount: 0, syntax: syntax), locale: Locale(identifier: "en"))
}

@MainActor
private func keyEvent(_ keyCode: UInt16, characters: String = "\r") throws -> NSEvent {
    try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                  context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                  isARepeat: false, keyCode: keyCode))
}

@Suite("Contents view", .serialized)
@MainActor
struct MarkupContentsViewTests {
    private let markdown = "# First\n\ntext\n\n## Second\n\n### Third\n\n# Fourth"

    private func shown() -> MarkupContentsView {
        let view = MarkupContentsView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        view.display(modes(.markdown, markdown, syntax: .markdown), mode: .contents, style: style())
        return view
    }

    @Test func listsEveryHeadingIndentedByLevel() throws {
        let view = shown()
        #expect(view.numberOfRows(in: view.tableView) == 4)
        #expect(view.headings.map(\.level) == [1, 2, 3, 1])
        let cells = (0..<4).compactMap { view.tableView(view.tableView, viewFor: nil, row: $0) as? ContentsCell }
        #expect(cells.map { $0.field.stringValue } == ["First", "Second", "Third", "Fourth"])
        #expect(cells.first?.field.toolTip == nil)
        view.layoutSubtreeIfNeeded()
        let insets = cells.map { cell -> CGFloat in
            cell.layoutSubtreeIfNeeded()
            return cell.field.frame.minX
        }
        #expect(insets[0] < insets[1] && insets[1] < insets[2] && insets[3] == insets[0])

        let longHeadingView = MarkupContentsView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        longHeadingView.display(
            modes(.markdown, "# A Very Long Section Heading That Wraps In Narrow Sidebars", syntax: .markdown),
            mode: .contents,
            style: style()
        )
        let longCell = try #require(longHeadingView.tableView(longHeadingView.tableView, viewFor: nil, row: 0) as? ContentsCell)
        #expect(longCell.field.toolTip == "A Very Long Section Heading That Wraps In Narrow Sidebars")
    }

    @Test func choosingAHeadingNavigatesToItsRangeInTheRenderedText() throws {
        let view = shown()
        var received: [(NativePreviewMode, NSRange)] = []
        view.navigate = { received.append(($0, $1)) }
        view.activate(row: 1)
        let rendered = try #require(view.headings.indices.contains(1) ? view.headings[1] : nil)
        #expect(received.count == 1)
        #expect(received[0].0 == .rendered)
        #expect(received[0].1 == rendered.range)
        view.activate(row: 99)
        view.activate(row: -1)
        #expect(received.count == 1)
    }

    @Test func returnAndEnterShowTheHeadingButSpaceAndArrowsDoNot() throws {
        let view = shown()
        var activations: [Int] = []
        view.navigate = { _, range in activations.append(range.location) }
        view.tableView.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        view.tableView.keyDown(with: try keyEvent(36))
        view.tableView.keyDown(with: try keyEvent(76, characters: "\u{3}"))
        #expect(activations.count == 2)
        #expect(Set(activations).count == 1)
        // Space belongs to Quick Look (decision 027, amendment 10), and moving with the arrow keys never navigates.
        view.tableView.keyDown(with: try keyEvent(49, characters: " "))
        view.tableView.keyDown(with: try keyEvent(125, characters: String(UnicodeScalar(NSDownArrowFunctionKey)!)))
        #expect(activations.count == 2)
    }

    @Test func rowsExposeLocalizedAccessibilityLabelAndHint() throws {
        let view = shown()
        let cell = try #require(view.tableView(view.tableView, viewFor: nil, row: 1) as? ContentsCell)
        let expected = PreviewStrings.format(.markupContentsItem, arguments: [Int64(2), "Second"], locale: Locale(identifier: "en"))
        #expect(cell.field.accessibilityLabel() == expected)
        #expect(cell.field.accessibilityHelp() == PreviewStrings.text(.markupContentsHelp))
        #expect(view.tableView.accessibilityLabel() == PreviewStrings.text(.previewModeContents))
    }

    @Test func restylingKeepsTheSelectionAndClearDropsEverything() throws {
        let view = shown()
        view.tableView.selectRowIndexes(IndexSet(integer: 3), byExtendingSelection: false)
        view.display(modes(.markdown, markdown, syntax: .markdown), mode: .contents, style: style(theme: .dark))
        #expect(view.tableView.selectedRow == 3)
        view.clear()
        #expect(view.headings.isEmpty)
        #expect(view.numberOfRows(in: view.tableView) == 0)
        var called = false
        view.navigate = { _, _ in called = true }
        view.activate(row: 0)
        #expect(!called)
    }

    @Test func aReplacementDocumentReplacesTheListAndResetsTheSelection() throws {
        let view = shown()
        view.tableView.selectRowIndexes(IndexSet(integer: 3), byExtendingSelection: false)
        view.display(modes(.latex, "\\section{A}\n\\section{B}", syntax: .latex), mode: .contents, style: style())
        #expect(view.headings.map(\.title) == ["A", "B"])
        #expect(view.tableView.selectedRow == 0)
    }

    @Test func copyWritesOnlySelectedSafeTitlesToAPrivatePasteboardOwner() throws {
        let view = shown()
        view.tableView.moveToEndOfDocument(nil)
        #expect(view.tableView.selectedRow == 3)
        view.tableView.moveToBeginningOfDocument(nil)
        #expect(view.tableView.selectedRow == 0)
        view.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("contents-copy-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        view.pasteboard = pasteboard
        var copies: [PreviewCopyEvent] = []
        view.copyHandler = { copies.append($0) }
        let menu = try #require(view.tableView.contextMenu(forRow: 1))
        #expect(menu.items.map(\.title) == [PreviewStrings.text(.interactionCopy), PreviewStrings.text(.interactionCopyAll)])
        let copyItem = try #require(menu.items.first)
        #expect(view.tableView.sendAction(copyItem.action, to: copyItem.target))
        #expect(pasteboard.string(forType: .string) == "Second")
        #expect(copies == [.rows(1)])
        view.tableView.deselectAll(nil)
        view.tableView.copy(nil)
        #expect(copies == [.rows(1)] && pasteboard.string(forType: .string) == "Second")
        view.display(
            modes(.markdown, "# First\n\ntext\n\n## Second ••••\n\n### Third\n\n# Fourth", syntax: .markdown),
            mode: .contents,
            style: style()
        )
        _ = menu.items[1].target?.perform(menu.items[1].action, with: menu.items[1])
        #expect(pasteboard.string(forType: .string) == "First\n  Second ••••\n    Third\nFourth")
        #expect(copies == [.rows(1), .text])
    }

    @Test func concealedHeadingTextStaysConcealed() throws {
        let view = MarkupContentsView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        view.display(modes(.markdown, "# Token ••••\n\n## Second", syntax: .markdown), mode: .contents, style: style())
        #expect(view.headings.first?.title == "Token ••••")
        let cell = try #require(view.tableView(view.tableView, viewFor: nil, row: 0) as? ContentsCell)
        #expect(cell.field.stringValue == "Token ••••")
    }
}

@Suite("References view", .serialized)
@MainActor
struct MarkupReferencesViewTests {
    private let bib = "@article{lovelace, author = {Lovelace, Ada}, title = {Notes}, journal = {Memoirs}, year = {1843}}\n@book{knuth, author = {Knuth, Donald E.}, title = {The TeXbook}, publisher = {Addison-Wesley}, year = {1984}}"

    private func shown() -> MarkupReferencesView {
        let view = MarkupReferencesView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.display(modes(.bibtex, bib, syntax: .bibtex), mode: .references, style: style())
        return view
    }

    @Test func offersTheFourStylesAndStartsWithAPA() throws {
        let view = shown()
        #expect(view.keyboardFocusTarget === view.textView)
        #expect(view.styleLabel.toolTip == PreviewStrings.text(.markupReferencesStyleLabel))
        #expect(view.styleControl.segmentCount == 4)
        #expect((0..<4).map { view.styleControl.label(forSegment: $0) } == BibliographyStyle.allCases.map { PreviewStrings.text($0.title) })
        #expect((0..<4).map { view.styleControl.toolTip(forSegment: $0) } == BibliographyStyle.allCases.map { PreviewStrings.text($0.title) })
        #expect(view.selectedStyle == .apa)
        #expect(view.textView.string.hasPrefix("Knuth, D. E. (1984)."))
        #expect(view.textView.string.contains("Lovelace, A. (1843). Notes. Memoirs."))
    }

    @Test func choosingAStyleReformatsTheListWithoutChangingTheSource() throws {
        let view = shown()
        for (index, expectedPrefix) in [(1, "Knuth, Donald E."), (2, "Knuth, Donald E. 1984."), (3, "[1] A. Lovelace")] {
            view.styleControl.selectedSegment = index
            #expect(view.styleControl.sendAction(view.styleControl.action, to: view.styleControl.target))
            #expect(view.textView.string.hasPrefix(expectedPrefix), "style \(index): \(view.textView.string.prefix(40))")
        }
        #expect(view.selectedStyle == .ieee)
        // The style choice survives a restyle (appearance change) of the same bibliography.
        view.display(modes(.bibtex, bib, syntax: .bibtex), mode: .references, style: style(theme: .dark))
        #expect(view.selectedStyle == .ieee)
        #expect(view.textView.string.hasPrefix("[1] A. Lovelace"))
    }

    @Test func italicDecorationsAreAppliedAsFontTraits() throws {
        let view = shown()
        let storage = try #require(view.textView.textStorage)
        let range = (view.textView.string as NSString).range(of: "The TeXbook")
        #expect(range.location != NSNotFound)
        let font = try #require(storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
        #expect(NSFontManager.shared.traits(of: font).contains(.italicFontMask))
        let plain = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(!NSFontManager.shared.traits(of: plain).contains(.italicFontMask))
    }

    @Test func accessibilityAndSelectableTextAndNoLinks() throws {
        let view = shown()
        #expect(view.textView.isSelectable)
        #expect(!view.textView.isEditable)
        #expect(view.textView.usesFindBar)
        #expect(view.styleControl.accessibilityLabel() == PreviewStrings.text(.markupReferencesStyleLabel))
        #expect(view.textView.accessibilityLabel() == PreviewStrings.format(.markupReferencesAccessibility, arguments: [Int64(2)], locale: Locale(identifier: "en")))
        let storage = try #require(view.textView.textStorage)
        var foundLink = false
        storage.enumerateAttribute(.link, in: NSRange(location: 0, length: storage.length)) { value, _, _ in if value != nil { foundLink = true } }
        #expect(!foundLink)
    }

    @Test func clearRemovesTheListSoAReplacementNeverShowsStaleReferences() throws {
        let view = shown()
        view.clear()
        #expect(view.textView.string.isEmpty)
        view.display(modes(.bibtex, "@misc{x, title = {Other}}", syntax: .bibtex), mode: .references, style: style())
        #expect(!view.textView.string.contains("Knuth"))
        #expect(view.textView.string.contains("Other"))
    }

    @Test func restylingKeepsTheSelectionBecauseTheTextIsNotReplaced() throws {
        let view = shown()
        view.textView.setSelectedRange(NSRange(location: 3, length: 5))
        view.display(modes(.bibtex, bib, syntax: .bibtex), mode: .references, style: style(theme: .dark))
        #expect(view.textView.selectedRange() == NSRange(location: 3, length: 5))
    }

    @Test func concealedFieldsStayConcealedInTheFormattedList() throws {
        let view = MarkupReferencesView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.display(modes(.bibtex, "@misc{x, author = {Doe, Jane}, title = {Safe}, year = {2020}, doi = ••••}", syntax: .bibtex), mode: .references, style: style())
        #expect(view.textView.string.contains("https://doi.org/••••"))
    }

    @Test func compactWidthHidesStyleLabelAndShrinksSegmentedControl() throws {
        let view = MarkupReferencesView(frame: NSRect(x: 0, y: 0, width: 240, height: 400))
        view.display(modes(.bibtex, bib, syntax: .bibtex), mode: .references, style: style())
        view.layoutSubtreeIfNeeded()
        #expect(view.styleLabel.isHidden)
        #expect(view.styleControl.controlSize == .small)
        view.setFrameSize(NSSize(width: 600, height: 400))
        view.layoutSubtreeIfNeeded()
        #expect(!view.styleLabel.isHidden)
        #expect(view.styleControl.controlSize == .regular)
    }
}

@Suite("Markup in the native preview", .serialized)
@MainActor
struct NativeMarkupPreviewTests {
    private func presentation(_ id: FormatID, _ text: String, syntax: TextSyntax) -> TextPresentation {
        TextPresentation(formatID: id, text: text, lineCount: 1, byteCount: text.utf8.count, encoding: .utf8, redactionCount: 0, syntax: syntax)
    }

    private func mainTextView(_ view: NativePreviewView) -> NSTextView? {
        view.scrollView.documentView as? NSTextView
    }

    private func displayedText(_ view: NativePreviewView) -> String? { mainTextView(view)?.string }

    @Test func aMarkupDocumentOpensRenderedAndOffersContents() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        view.display(.ready(presentation(.latex, "\\section{One}\nBody text.\n\\section{Two}", syntax: .latex)))
        let control = view.modeControl
        #expect(control.segmentCount == 3)
        #expect((0..<3).map { control.label(forSegment: $0) } == [.previewModeSource, .previewModeRendered, .previewModeContents].map { PreviewStrings.text($0) })
        #expect(control.selectedSegment == 1)
        #expect(displayedText(view)?.hasPrefix("One") == true)
    }

    @Test func theContentsListNavigatesBackToTheRenderedHeadingAndSelectsIt() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        view.display(.ready(presentation(.markdown, "# Alpha\n\ntext\n\n## Beta\n\nmore text", syntax: .markdown)))
        let control = view.modeControl
        control.selectedSegment = 2
        #expect(control.sendAction(control.action, to: control.target))
        let contents = try #require(descendants(of: MarkupContentsView.self, in: view).first)
        #expect(!contents.isHidden)
        contents.activate(row: 1)
        let textView = try #require(mainTextView(view))
        #expect(contents.isHidden)
        #expect((textView.string as NSString).substring(with: textView.selectedRange()) == "Beta")
        #expect(control.selectedSegment == 1)
    }

    @Test func contentsSelectionCopiesThroughTheHostWithOneConfirmation() throws {
        let host = InteractionHarness()
        defer { host.release() }
        let scheduler = ManualChromeScheduler()
        host.view.chromeScheduler = scheduler
        host.show(presentation(.markdown, "# Alpha\n\ntext\n\n## Token ••••\n\nbody", syntax: .markdown))
        let control = host.view.modeControl
        control.selectedSegment = try #require(host.view.displayedModes.firstIndex(of: .contents))
        #expect(control.sendAction(control.action, to: control.target))
        host.view.layoutSubtreeIfNeeded()
        let contents = try #require(host.view.contentView(for: .contents) as? MarkupContentsView)
        contents.pasteboard = host.pasteboard
        host.announcements.texts.removeAll()
        contents.tableView.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        contents.tableView.copy(nil)
        let copied = PreviewStrings.text(.chipCopied)
        #expect(host.pasteboard.string(forType: .string) == "Token ••••")
        #expect(host.announcements.texts == [copied])
        #expect(host.view.chip.text == copied && scheduler.waiting.count == 1)
        contents.tableView.deselectAll(nil)
        contents.tableView.copy(nil)
        #expect(host.announcements.texts == [copied] && scheduler.waiting.count == 1)
        scheduler.runWaiting()
        #expect(host.view.chip.isHidden && host.announcements.texts == [copied])
    }

    @Test func aBibTeXDocumentOffersTheReferencesModeAndAReplacementClearsIt() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        view.display(.ready(presentation(.bibtex, "@misc{a, author = {Doe, Jane}, title = {Safe}, year = {2020}}", syntax: .bibtex)))
        let control = view.modeControl
        let references = PreviewStrings.text(.markupModeReferences)
        let index = try #require((0..<control.segmentCount).first { control.label(forSegment: $0) == references })
        control.selectedSegment = index
        #expect(control.sendAction(control.action, to: control.target))
        let referencesView = try #require(descendants(of: MarkupReferencesView.self, in: view).first)
        #expect(!referencesView.isHidden)
        #expect(referencesView.textView.string.contains("Doe, J. (2020). Safe."))
        view.display(.disabledByUser(.bibtex))
        #expect(referencesView.textView.string.isEmpty)
        #expect(referencesView.isHidden)
    }

    @Test func renderedMarkupTextStaysSelectableAndNeverCarriesLinks() throws {
        let view = NativePreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        view.display(.ready(presentation(.asciidoc, "A https://example.invalid/x[link] here.", syntax: .asciidoc)))
        let textView = try #require(mainTextView(view))
        #expect(textView.isSelectable && !textView.isEditable)
        #expect(textView.string == "A link (https://example.invalid/x) here.")
        let storage = try #require(textView.textStorage)
        #expect(storage.attribute(.link, at: 3, effectiveRange: nil) == nil)
    }
}
