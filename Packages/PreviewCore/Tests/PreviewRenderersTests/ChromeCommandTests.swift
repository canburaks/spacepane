import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// How the preview answers the command table (decision 027, Q-38): the Option-Command number chords that pick a
/// view, the focus that follows the content, the context menu built from the table, the zoom decision of a mode
/// view, and the services (announcer, copy reporting) the preview hands to the views it hosts.
@Suite("Chrome commands", .serialized)
@MainActor
struct ChromeCommandTests {
    private let english = Locale(identifier: "en")
    private let chord: NSEvent.ModifierFlags = [.option, .command]
    private let json = #"{"name":"demo","items":[1,2,3]}"#
    private let headings = "# Alpha\n\ntext\n\n## Beta\n\nmore text"

    private func harness() -> InteractionHarness {
        let host = InteractionHarness()
        host.view.chromeScheduler = ManualChromeScheduler()
        return host
    }

    private func comic() -> TextPresentation {
        let summary = #"{"title":"Synthetic","series":"Series","issueNumber":"7","writer":"Writer","pageCount":3,"shownPages":3,"partial":false}"#
        return TextPresentation(formatID: .comicBook, text: summary, lineCount: 1, byteCount: summary.utf8.count,
                                encoding: .utf8, redactionCount: 0, syntax: .json, images: testPages(3))
    }

    // MARK: The mode chords

    @Test func aChordShowsTheViewItNumbersAndSaysItsName() throws {
        let host = harness()
        defer { host.release() }
        host.show(plainPresentation(json, format: .json, syntax: .json))
        let modes = host.view.displayedModes
        let outline = try #require(modes.firstIndex(of: .outline)) + 1
        #expect(host.press("1", chord))
        #expect(host.view.selectedMode == modes[0] && !host.textView.isHidden)
        host.announcements.texts.removeAll()
        #expect(host.press(String(outline), chord))
        #expect(host.view.selectedMode == .outline && !host.view.outlineView.isHidden && host.textView.isHidden)
        #expect(host.view.modeControl.selectedSegment == outline - 1)
        #expect(host.announcements.texts == [PreviewStrings.text(.previewModeOutline)])
        // And back: the first view is Source.
        host.announcements.texts.removeAll()
        #expect(host.press("1", chord))
        #expect(host.view.selectedMode == .source && host.view.outlineView.isHidden)
        #expect(host.announcements.texts == [PreviewStrings.text(.previewModeSource)])
    }

    @Test func theChordForTheViewAlreadyShownIsConsumedAndQuiet() {
        let host = harness()
        defer { host.release() }
        host.show(plainPresentation(json, format: .json, syntax: .json))
        host.press("1", chord)
        host.announcements.texts.removeAll()
        #expect(host.press("1", chord))
        #expect(host.view.selectedMode == .source && host.announcements.texts.isEmpty)
    }

    @Test func focusInsideThePreviewFollowsTheContentAndFocusNowhereStaysNowhere() throws {
        let host = harness()
        defer { host.release() }
        host.show(plainPresentation(json, format: .json, syntax: .json))
        let outline = try #require(host.view.displayedModes.firstIndex(of: .outline)) + 1
        host.press("1", chord)
        // Nothing has focus: the view changes and focus is not taken.
        #expect(host.window.firstResponder === host.window)
        #expect(host.press(String(outline), chord))
        #expect(host.window.firstResponder === host.window)
        // Focus in the text goes to the outline when the outline replaces it, and back.
        host.press("1", chord)
        #expect(host.window.makeFirstResponder(host.textView))
        #expect(host.press(String(outline), chord))
        let rows = try #require(host.view.outlineView.documentView)
        #expect(host.window.firstResponder === rows)
        #expect(host.press("1", chord))
        #expect(host.window.firstResponder === host.textView)
    }

    @Test func aChordIsDeclinedWithoutAControlWithoutThatViewInAStateAndWithFocusElsewhere() {
        let host = harness()
        defer { host.release() }
        // One view only: the control is hidden and the keys stay free.
        host.show(plainPresentation("just words"))
        #expect(host.view.displayedModes.count == 1 && host.view.modeControl.isHidden)
        #expect(!host.press("1", chord) && !host.press("2", chord))
        #expect(host.announcements.texts.isEmpty)
        // A number past the last view, and the number key without Option.
        host.show(plainPresentation(json, format: .json, syntax: .json), resetsContentState: true)
        let before = host.view.selectedMode
        #expect(host.view.displayedModes.count < 9 && !host.press("9", chord))
        #expect(!host.press("2", .command) && host.view.selectedMode == before)
        // A state has no views.
        host.view.display(.unavailable(.missingFile))
        #expect(!host.press("2", chord))
        // Focus in a text field elsewhere in the window is not the preview's to take.
        let container = NSView(frame: host.view.frame)
        host.window.contentView = container
        container.addSubview(host.view)
        let other = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 20))
        container.addSubview(other)
        host.show(plainPresentation(json, format: .json, syntax: .json), resetsContentState: true)
        let shown = host.view.selectedMode
        host.window.makeFirstResponder(other)
        #expect(!host.view.ownsKeyboardFocus && !host.press("2", chord))
        #expect(host.view.selectedMode == shown)
    }

    @Test func eachSegmentShowsItsChordAsATooltip() throws {
        let host = harness()
        defer { host.release() }
        host.show(plainPresentation(headings, format: .markdown, syntax: .markdown))
        let control = host.view.modeControl
        #expect(control.segmentCount == host.view.displayedModes.count && control.segmentCount >= 3)
        for index in 0..<control.segmentCount {
            #expect(control.toolTip(forSegment: index) == "⌥⌘\(index + 1)", "segment \(index)")
        }
    }

    // MARK: A link that switches the view

    @Test func aLinkThatSwitchesTheViewSaysItsNameAndLandsInTheText() throws {
        let host = harness()
        defer { host.release() }
        host.show(plainPresentation(headings, format: .markdown, syntax: .markdown))
        let contentsNumber = try #require(host.view.displayedModes.firstIndex(of: .contents)) + 1
        #expect(host.press(String(contentsNumber), chord))
        #expect(host.view.selectedMode == .contents)
        let contents = try #require(host.view.contentView(for: .contents) as? any SafeModeContentView)
        host.announcements.texts.removeAll()
        contents.navigate?(.rendered, NSRange(location: 0, length: 5))
        #expect(host.view.selectedMode == .rendered)
        #expect(host.announcements.texts == [PreviewStrings.text(.previewModeRendered)])
        #expect((host.textView.string as NSString).substring(with: host.textView.selectedRange()) == "Alpha")
        #expect(host.window.firstResponder === host.textView)
    }

    @Test func aLinkWithARangeThatNoLongerExistsStillLandsInTheText() throws {
        let host = harness()
        defer { host.release() }
        host.show(plainPresentation(headings, format: .markdown, syntax: .markdown))
        let contentsNumber = try #require(host.view.displayedModes.firstIndex(of: .contents)) + 1
        host.press(String(contentsNumber), chord)
        let contents = try #require(host.view.contentView(for: .contents) as? any SafeModeContentView)
        contents.navigate?(.source, NSRange(location: 10_000, length: 1))
        #expect(host.view.selectedMode == .source && !host.textView.isHidden)
        #expect(host.window.firstResponder === host.textView)
    }

    // MARK: Copy All

    @Test func copyAllWorksWhileThePreviewsOwnTextHasFocusButNotInAnEditableField() throws {
        let host = harness()
        defer { host.release() }
        let text = "token = ••••\nplain"
        host.show(plainPresentation(text, redactions: 1))
        #expect(host.window.makeFirstResponder(host.textView))
        #expect(host.press("c", [.command, .shift]))
        #expect(host.pasteboard.string(forType: .string) == text)
        // The Go to Line field is editable: the key stays its own.
        host.pasteboard.clearContents()
        host.press("l", .command)
        #expect(!host.press("c", [.command, .shift]))
        #expect(host.pasteboard.string(forType: .string) == nil)
    }

    // MARK: The context menu

    private func commandMenu(_ host: InteractionHarness) throws -> [NSMenuItem] {
        let menu = try #require(host.view.textView(host.textView, menu: NSMenu(), for: host.keyEvent("x", []), at: 0))
        return menu.items.filter { $0.representedObject is PreviewCommandAction }
    }

    private func item(_ key: PreviewStrings.Key, in items: [NSMenuItem]) throws -> NSMenuItem {
        try #require(items.first { $0.title == PreviewStrings.text(key) })
    }

    private func choose(_ item: NSMenuItem) throws {
        let action = try #require(item.representedObject as? PreviewCommandAction)
        action.run(item)
    }

    @Test func theContextMenuListsTheTablesCommandsWithTheirChords() throws {
        let host = harness()
        defer { host.release() }
        host.show(plainPresentation("secret = ••••\nnext", redactions: 1))
        let items = try commandMenu(host)
        #expect(items.count == PreviewCommand.contextMenuCommands.count)
        let copyAll = try item(.interactionCopyAll, in: items)
        #expect(copyAll.keyEquivalent == "c" && copyAll.keyEquivalentModifierMask == [.command, .shift])
        let zoomIn = try item(.interactionZoomIn, in: items)
        #expect(zoomIn.keyEquivalent == "+" && zoomIn.keyEquivalentModifierMask == .command)
        for key in [PreviewStrings.Key.interactionGoToLine, .interactionZoomOut, .interactionZoomReset] {
            _ = try item(key, in: items)
        }
    }

    @Test func choosingAnItemRunsTheSameHandlerAsItsKey() throws {
        let host = harness()
        defer { host.release() }
        let text = "secret = ••••\nnext"
        host.show(plainPresentation(text, redactions: 1), typography: PreviewTypography(fontSize: 13))
        let items = try commandMenu(host)
        try choose(item(.interactionCopyAll, in: items))
        #expect(host.pasteboard.string(forType: .string) == text)
        #expect(host.view.chip.text == PreviewStrings.text(.chipCopied))
        try choose(item(.interactionGoToLine, in: items))
        #expect(host.view.accessoryBar.content == .goToLine)
        try choose(item(.interactionZoomIn, in: items))
        #expect(host.view.zoomChip != nil)
        try choose(item(.interactionZoomReset, in: items))
        #expect(host.view.zoomChip == nil)
    }

    @Test func copyAllFromTheMenuIsADeliberateRequestEvenWhileAnEditableFieldHasFocus() throws {
        let host = harness()
        defer { host.release() }
        let text = "secret = ••••\nnext"
        host.show(plainPresentation(text, redactions: 1))
        let items = try commandMenu(host)
        host.press("l", .command)
        #expect(!host.press("c", [.command, .shift]))
        try choose(item(.interactionCopyAll, in: items))
        #expect(host.pasteboard.string(forType: .string) == text)
    }

    // MARK: Zoom

    @Test func aViewWithNothingToScaleLeavesTheZoomShortcutAlone() throws {
        let host = harness()
        defer { host.release() }
        host.view.display(.ready(comic()), locale: english)
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.selectedMode == .pages)
        let pages = try #require(host.view.shownModeView)
        #expect(!pages.respondsToTextZoom)
        #expect(!host.press("=", .command) && !host.press("-", .command) && !host.press("0", .command))
        #expect(host.view.zoomChip == nil && host.view.chip.isHidden && host.announcements.texts.isEmpty)
        // The same shortcut still zooms text in a text mode.
        host.show(plainPresentation(numberedLines(10)), typography: PreviewTypography(fontSize: 13), resetsContentState: true)
        #expect(host.view.shownModeView == nil)
        #expect(host.press("=", .command) && host.view.zoomChip != nil)
    }

    // MARK: Services handed to hosted views

    @Test func theViewsTheMidiStripTheFilesAndTheTreeSpeakThroughThePreviewsAnnouncer() throws {
        let host = harness()
        defer { host.release() }
        let midi = try #require(descendants(of: NativeMIDIPreviewView.self, in: host.view).first)
        #expect(midi.announcer === host.view.announcer)
        host.show(listingPresentation(archiveListingJSON, format: .zip))
        let files = try #require(descendants(of: NativeListingFilesView.self, in: host.view).first)
        #expect(files.announcer === host.view.announcer && files.table.announcer === host.view.announcer)
        // A copy in the hosted table is the preview's chip and one announcement.
        files.copyHandler?(.rows(2))
        #expect(host.view.chip.text == PreviewStrings.text(.chipCopied))
        #expect(host.announcements.texts == [PreviewStrings.text(.chipCopied)])
        let tree = try #require(host.view.displayedModes.firstIndex(of: .tree)) + 1
        #expect(host.press(String(tree), chord))
        let treeView = try #require(descendants(of: NativeListingTreeView.self, in: host.view).first)
        #expect(treeView.announcer === host.view.announcer)
    }

    @Test func theMidiStripDrawsItsStatusInThePreviewsQuietInk() throws {
        let host = harness()
        defer { host.release() }
        // Solarized Light is a scheme whose muted ink needs the size cue, so ink and size both show the wiring.
        let style = PreviewSyntaxStyle(lightScheme: .solarizedLight, darkScheme: .standard)
        host.view.display(.ready(plainPresentation("safe words")), theme: .light, syntaxStyle: style, locale: english)
        let midi = try #require(descendants(of: NativeMIDIPreviewView.self, in: host.view).first)
        let status = try #require(descendants(of: NSTextField.self, in: midi).first {
            $0.stringValue == PreviewStrings.text(.midiNoAutoplay)
        })
        let palette = NativeTextPalette(theme: .light, isDark: false,
                                        increasedContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
                                        style: style)
        #expect(status.textColor == palette.muted)
        #expect(palette.mutedUsesSizeCue == (status.font?.pointSize == PreviewChrome.mutedPointSize))
    }

    @Test func theThreeDimensionalViewSpeaksThroughThePreviewsAnnouncerToo() throws {
        let host = harness()
        defer { host.release() }
        let mesh = try PreviewMesh(positions: [SIMD3<Float>(-1, -1, 0), SIMD3<Float>(1, -1, 0), SIMD3<Float>(0, 1, 0)],
            normals: Array(repeating: SIMD3<Float>(0, 0, 1), count: 3), indices: [0, 1, 2],
            bounds: GeometryBounds(minimum: SIMD3<Double>(0, 0, 0), maximum: SIMD3<Double>(20, 20, 1)), faceCount: 1)
        host.view.display(.geometryReady(GeometryPresentation(formatID: .meshSTL, mesh: mesh, byteCount: 100)),
                          locale: english)
        let geometry = try #require(descendants(of: NativeGeometryPreviewView.self, in: host.view).first)
        #expect(geometry.announcer === host.view.announcer)
    }

    // MARK: The text view

    @Test func theTextViewIsAHandBuiltTextKitOneStackThatKeepsItselfAlive() {
        let view = PreviewTextView.makeTextKit1()
        #expect(view.textLayoutManager == nil)
        #expect(view.textContainer?.textView === view && view.layoutManager != nil && view.textStorage != nil)
        view.string = "alpha"
        #expect(view.textStorage?.string == "alpha")
        // The preview's own text view is made the same way and is the subclass the copy report needs.
        let host = harness()
        defer { host.release() }
        #expect(type(of: host.view.textView) == PreviewTextView.self)
        #expect(host.view.textView.textLayoutManager == nil && host.view.textView.copyHandler != nil)
    }

    @Test func modeChordsFocusHostedTablesAndReferencesTextAndEnableFindInReferences() throws {
        let host = harness()
        defer { host.release() }
        host.show(listingPresentation(archiveListingJSON, format: .zip))
        let sourceNumber = try #require(host.view.displayedModes.firstIndex(of: .source)) + 1
        #expect(host.press(String(sourceNumber), chord))
        #expect(host.window.makeFirstResponder(host.textView))
        let filesNumber = try #require(host.view.displayedModes.firstIndex(of: .files)) + 1
        #expect(host.press(String(filesNumber), chord))
        let filesView = try #require(host.view.shownModeView as? NativeListingFilesView)
        #expect(host.window.firstResponder === filesView.table.tableView)

        host.show(plainPresentation("@article{k, author = {Knuth}, title = {TeX}, journal = {J}, year = {1984}}", format: .bibtex, syntax: .bibtex), resetsContentState: true)
        #expect(host.window.makeFirstResponder(host.textView))
        let referencesNumber = try #require(host.view.displayedModes.firstIndex(of: .references)) + 1
        #expect(host.press(String(referencesNumber), chord))
        let referencesView = try #require(host.view.shownModeView as? MarkupReferencesView)
        #expect(host.window.firstResponder === referencesView.textView)
        #expect(referencesView.textView.delegate === host.view)
        let commands = host.view.commandAvailability.commands
        #expect(commands.contains(.find) && commands.contains(.findNext) && commands.contains(.findPrevious))
        #expect(!commands.contains(.goToLine))
        #expect(host.press("c", [.command, .shift]))
        #expect(host.pasteboard.string(forType: .string) == referencesView.textView.string)
        let menu = try #require(host.view.textView(referencesView.textView, menu: NSMenu(), for: host.keyEvent("x", []), at: 0))
        #expect(menu.items.map(\.title).contains(PreviewStrings.text(.interactionCopyAll)))
        #expect(!menu.items.map(\.title).contains(PreviewStrings.text(.interactionGoToLine)))
        host.window.makeFirstResponder(referencesView.styleControl)
        #expect(host.press("f", .command))
        #expect((host.window.firstResponder as? NSView)?.isDescendant(of: referencesView) == true)
        #expect(host.window.firstResponder !== referencesView.styleControl)
    }
}
