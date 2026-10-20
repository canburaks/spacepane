import AppKit
import PreviewContracts

/// The preview's reading tools: Go to Line, Copy All, the outline filter and temporary zoom, and the chip that
/// confirms a copy or shows the zoom level. Every one works on the displayed, already-concealed text or nodes; none
/// reads a file, a preference or the pasteboard of the user unless the user asks to copy.
extension NativePreviewView {
    // MARK: Wiring

    func wireInteractionBars() {
        accessoryBar.filterBar.onChange = { [weak self] text in self?.filterTextChanged(text) }
        accessoryBar.filterBar.onAdvance = { [weak self] forward in _ = self?.outlineView.selectAdjacentMatch(forward: forward) }
        accessoryBar.filterBar.onReturnToContent = { [weak self] in self?.focusOutline() }
        accessoryBar.filterBar.onCopyPath = { [weak self] in _ = self?.copySelectedOutlinePath() }
        outlineView.onFilterResult = { [weak self] summary in self?.accessoryBar.filterBar.show(summary) }
        outlineView.onSelectionChange = { [weak self] path in self?.accessoryBar.filterBar.showPath(path) }
        accessoryBar.goToLineBar.onSubmit = { [weak self] input in self?.submitGoToLine(input) }
        accessoryBar.goToLineBar.onDismiss = { [weak self] in self?.dismissGoToLine() }
    }

    /// Forgets zoom, the filter and an open Go to Line bar: a new request starts clean.
    func resetInteractionState() {
        zoom.reset()
        goToLineIsOpen = false
        clearFilter()
        accessoryBar.filterBar.showPath(nil)
        accessoryBar.show(.none)
        accessoryHeightConstraint?.constant = 0
        cancelCopyChip()
    }

    func updateAccessoryBar(showsOutline: Bool) {
        // Without typed input the outline filter would be a dead field, so the bar stays empty.
        let showsFilter = showsOutline && acceptsTypedInput
        let content: PreviewAccessoryBar.Content = showsFilter ? .filter : (goToLineIsOpen ? .goToLine : .none)
        if !showsFilter {
            clearFilter()
            accessoryBar.filterBar.showPath(nil)
        }
        accessoryBar.show(content)
        accessoryHeightConstraint?.constant = accessoryBar.requiredHeight
    }

    // MARK: Chip

    /// The temporary zoom as the chip shows it ("110%") and as it is spoken, with the reset reminder. Nil at the
    /// saved size. The read-only and provider captions live in `PreviewInfoBadge`.
    var zoomChip: (shown: String, spoken: String)? {
        guard !zoom.isDefault, zoom.scale(of: typography) != nil else { return nil }
        let shown = zoomLevelText
        return (shown: shown, spoken: PreviewStrings.format(.interactionZoomStatus, arguments: [shown], locale: presentationLocale))
    }

    /// The temporary zoom as a percentage in the presentation locale ("110%"); "100%" at the saved size.
    var zoomLevelText: String {
        let percent = NumberFormatter()
        percent.numberStyle = .percent
        percent.locale = presentationLocale
        percent.maximumFractionDigits = 0
        return percent.string(from: NSNumber(value: zoom.scale(of: typography) ?? 1)) ?? ""
    }

    /// Shows the "Copied" confirmation while it lasts, otherwise the zoom level, otherwise nothing. The chip is
    /// derived from state, so every change that matters just calls this.
    func refreshChip() {
        if let message = copyChipText {
            chip.show(message)
        } else if let level = zoomChip {
            chip.show(level.shown, spoken: level.spoken)
        } else {
            chip.hide()
        }
    }

    /// The typography to draw with: the saved settings plus this preview's temporary zoom.
    var effectiveTypography: PreviewTypography { zoom.applying(to: typography) }

    // MARK: Keyboard

    /// Handles the preview's shortcuts. Returns false for anything not its own, so the event keeps travelling.
    func handleShortcut(_ shortcut: PreviewShortcut) -> Bool {
        guard commandAvailability.contains(shortcut.command) else { return false }
        switch shortcut {
        case .goToLine: return presentGoToLine()
        case .copyAll:
            // In an editable text field Command-Shift-C is not ours to take; the preview's own text is read-only.
            guard (window?.firstResponder as? NSText)?.isEditable != true else { return false }
            return copyAllSafeText()
        case .find: return performFind(.showFindInterface)
        case .findNext: return performFind(.nextMatch)
        case .findPrevious: return performFind(.previousMatch)
        case .zoomIn, .zoomOut, .zoomReset: return applyZoom(shortcut)
        }
    }

    /// Key equivalents act only while keyboard focus is inside this preview or nowhere in particular, so a
    /// text field elsewhere in a window is never overridden.
    var ownsKeyboardFocus: Bool {
        guard let window, !isHiddenOrHasHiddenAncestor else { return false }
        guard let responder = window.firstResponder, responder !== window else { return true }
        return (responder as? NSView)?.isDescendant(of: self) ?? false
    }

    var showsTextMode: Bool { hasDisplayableContent && !scrollView.isHidden && !textView.isHidden }
    var showsOutlineMode: Bool { hasDisplayableContent && !outlineView.isHidden }

    private func performFind(_ action: NSTextFinder.Action) -> Bool {
        guard acceptsTypedInput else { return false }
        if let targetTextView = showsTextMode ? textView : (shownModeView as? MarkupReferencesView)?.textView {
            let item = NSMenuItem()
            item.tag = action.rawValue
            if action == .showFindInterface { window?.makeFirstResponder(targetTextView) }
            targetTextView.performTextFinderAction(item)
            return true
        }
        if showsOutlineMode {
            switch action {
            case .showFindInterface: accessoryBar.filterBar.focus(); return true
            case .nextMatch: return outlineView.selectAdjacentMatch(forward: true)
            case .previousMatch: return outlineView.selectAdjacentMatch(forward: false)
            default: return false
            }
        }
        // A table has no text finder: Command-F opens its filter from anywhere in the preview, and the other find
        // commands are not advertised there (see `PreviewCommandAvailability.search`).
        if let table = shownTable { return action == .showFindInterface && table.showFilter() }
        return false
    }

    /// The table a table mode shows: the preview's own table in Table and Profile, or the table that a Files or Rows
    /// view hosts. Nil when no table is on screen. Command-F and the information panel's availability both read it,
    /// so they cannot disagree.
    var shownTable: NativeTablePreviewView? {
        if let hosted = shownModeView as? any PreviewHostsTable { return hosted.table }
        guard showsTableMode else { return nil }
        return contentView(for: selectedMode) as? NativeTablePreviewView
    }

    // MARK: Zoom

    private func applyZoom(_ shortcut: PreviewShortcut) -> Bool {
        // Zoom restyles text, outline, table and mode views; the 3D view has its own camera zoom.
        guard hasDisplayableContent, geometryPresentation == nil else { return false }
        // A mode view that scales its own content (a diagram, the page column) takes the key first, and one with
        // nothing to scale (a picture) leaves it alone: the temporary text zoom and its chip never apply there.
        if let view = shownModeView, let handled = view.zoomDecision(for: shortcut) { return handled }
        var changed = false
        switch shortcut {
        case .zoomIn: changed = zoom.zoomIn(from: typography)
        case .zoomOut: changed = zoom.zoomOut(from: typography)
        case .zoomReset: changed = !zoom.isDefault; zoom.reset()
        default: return false
        }
        // The key is consumed even at a bound, so reaching the limit never falls through to another handler.
        if changed {
            applyStyling()
            announce(zoomLevelText)
        }
        return true
    }

    // MARK: Copy All

    /// The text Copy All copies: the displayed text of a text mode, or for outline, table and derived modes
    /// the document's concealed text. It is never raw source: both come from the privacy-filtered presentation.
    var copyAllText: String? {
        guard hasDisplayableContent else { return nil }
        if showsTextMode { return textView.string }
        if let references = shownModeView as? MarkupReferencesView { return references.textView.string }
        return safePresentation?.text
    }

    @discardableResult
    func copyAllSafeText() -> Bool {
        guard let text = copyAllText, !text.isEmpty else { return false }
        let copied = TagCopySanitizer(safeDisplayedText: text, safetyLensFoundTags: safetyLensFoundTags).wholeText()
        guard plainTextCopyWriter(copied.text, pasteboard) else { return false }
        reportCopy(.text.removingTags(copied.removedTagScalarCount))
        return true
    }

    @discardableResult
    func copySelectedOutlinePath() -> Bool {
        guard let path = outlineView.selectedPath, !path.isEmpty else { return false }
        let copied = TagCopySanitizer(safeDisplayedText: path, safetyLensFoundTags: safetyLensFoundTags).wholeText()
        guard plainTextCopyWriter(copied.text, pasteboard) else { return false }
        reportCopy(.path.removingTags(copied.removedTagScalarCount))
        return true
    }

    // MARK: Copy feedback

    /// One feedback path for every copy: the chip for a moment and one announcement. A new copy replaces the chip
    /// and restarts its lifetime instead of stacking; a new generation and `suspendResources` cancel it. Every kind
    /// of event shows the same single string today; the kinds exist so a view can later say what it copied.
    func reportCopy(_ event: PreviewCopyEvent) {
        copyChipTimer?.cancel()
        let message = PreviewStrings.text(event.confirmationKey)
        copyChipText = message
        refreshChip()
        announce(message)
        copyChipTimer = chromeScheduler.schedule(after: PreviewChrome.chipDuration) { [weak self] in
            self?.endCopyChip()
        }
    }

    /// The chip's lifetime ended: the zoom level, or nothing, takes its place.
    func endCopyChip() {
        copyChipTimer = nil
        copyChipText = nil
        refreshChip()
    }

    /// Forgets a pending confirmation without touching the chip; the next `refreshChip` redraws it.
    func cancelCopyChip() {
        copyChipTimer?.cancel()
        copyChipTimer = nil
        copyChipText = nil
    }

    /// Gives hosted text, outline, table, tree and Contents views the preview's services: copies go to
    /// `reportCopy`, and spoken feedback goes through the preview's one announcer. Each successful copy
    /// produces one chip and one announcement.
    func adoptPreviewServices(_ view: NSView) {
        if let host = view as? any PreviewHostsTable { host.table.acceptsTypedInput = acceptsTypedInput }
        if let references = view as? MarkupReferencesView { references.textView.delegate = self }
        if let copier = view as? any PreviewSafeCopying {
            copier.pasteboard = pasteboard
            copier.tagCopyPolicy = { [weak self] in self?.safetyLensFoundTags ?? false }
        }
        if let reporter = view as? any PreviewCopyReporting {
            reporter.copyHandler = { [weak self] event in self?.reportCopy(event) }
        }
        if let speaker = view as? any PreviewAnnouncing {
            speaker.announcer = announcer
        }
    }

    /// Always evaluated for the current generation; a retained mode view cannot keep a previous finding gate.
    var safetyLensFoundTags: Bool {
        safePresentation?.findings.contains {
            // Generated listings report unsafe name characters without decoding a payload or scanning their summary.
            // The copy sanitizer still removes only actual unsafe Tag spans from that already-safe text.
            $0.kind == .hiddenUnicodeTags || $0.kind == .listingHiddenCharacters
        } ?? false
    }

    // MARK: Go to Line

    /// Opens the inline bar for the displayed text. Not available over outlines, tables and loading states.
    @discardableResult
    func presentGoToLine() -> Bool {
        guard acceptsTypedInput, showsTextMode, selectedMode != .rendered else { return false }
        goToLineIsOpen = true
        updateAccessoryBar(showsOutline: false)
        accessoryBar.goToLineBar.show(lineCount: currentLineIndex().count)
        layoutSubtreeIfNeeded()
        accessoryBar.goToLineBar.focus()
        return true
    }

    func dismissGoToLine() {
        guard goToLineIsOpen else { return }
        goToLineIsOpen = false
        updateAccessoryBar(showsOutline: false)
        window?.makeFirstResponder(textView)
    }

    /// The logical line index of the displayed text. The gutter keeps one for the same string; a stale one
    /// (it can lag a frame behind a replacement) is rebuilt rather than trusted.
    private func currentLineIndex() -> LogicalLineIndex {
        let index = lineNumberGutter.lineIndex
        return index.utf16Length == textView.string.utf16.count ? index : LogicalLineIndex(textView.string)
    }

    func submitGoToLine(_ input: String) {
        let text = textView.string as NSString
        let index = currentLineIndex()
        switch GoToLine.resolve(input, in: text, index: index) {
        case .success(let target):
            goToLineIsOpen = false
            updateAccessoryBar(showsOutline: false)
            reveal(target.range)
            announce(PreviewStrings.format(.interactionGoToLineJumped, arguments: [Int64(target.line), Int64(target.lineCount)],
                                           locale: presentationLocale))
        case .failure(let failure):
            let message: String
            switch failure {
            case .noLines: message = PreviewStrings.text(.interactionGoToLineNoLines)
            case .outOfRange(let count):
                message = PreviewStrings.format(.interactionGoToLineInvalid, arguments: [Int64(count)], locale: presentationLocale)
            }
            accessoryBar.goToLineBar.show(lineCount: index.count, error: message)
            announce(message)
        }
    }

    /// Selects `range` and scrolls so its line sits mid-view, then returns focus to the text.
    private func reveal(_ range: NSRange) {
        textView.setSelectedRange(range)
        if let line = lineRect(for: range) {
            let viewportHeight = scrollView.contentView.bounds.height
            let maximumY = max(0, textView.frame.height - viewportHeight)
            let y = min(max(line.midY + textView.textContainerOrigin.y - viewportHeight / 2, 0), maximumY)
            scrollView.contentView.scroll(to: NSPoint(x: scrollView.contentView.bounds.origin.x, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else {
            textView.scrollRangeToVisible(range)
        }
        window?.makeFirstResponder(textView)
    }

    private func lineRect(for range: NSRange) -> NSRect? {
        guard let manager = textView.layoutManager, manager.numberOfGlyphs > 0 || range.location == 0 else { return nil }
        if range.location >= (textView.string as NSString).length {
            let extra = manager.extraLineFragmentRect
            return extra.isEmpty ? nil : extra
        }
        let glyph = manager.glyphIndexForCharacter(at: range.location)
        guard glyph < manager.numberOfGlyphs else { return nil }
        return manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
    }

    // MARK: Outline filter

    func filterTextChanged(_ text: String) {
        let summary = outlineView.setFilter(text)
        // A count that updates while the reader is still typing queues behind the characters being echoed.
        if summary.isActive { announce(OutlineFilterBar.countText(for: summary), priority: .medium) }
    }

    /// Empties the filter field and shows every row again.
    func clearFilter() {
        if !accessoryBar.filterBar.text.isEmpty { accessoryBar.filterBar.text = "" }
        outlineView.setFilter("")
    }

    private func focusOutline() {
        if let documentView = outlineView.documentView { window?.makeFirstResponder(documentView) }
    }

    // MARK: Announcements

    /// Says `text` through the preview's announcer, which holds the policy; empty text is never announced.
    func announce(_ text: String, priority: NSAccessibilityPriorityLevel = .high) {
        announcer.announce(text, from: self, priority: priority)
    }
}

extension NativePreviewView: NSTextViewDelegate {
    /// Adds the preview's commands below the standard text menu. The titles and the shortcuts shown come from the
    /// command table; the preview answers the keys itself in `performKeyEquivalent`, and choosing an item runs the
    /// same handler.
    public func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        menu.addItem(.separator())
        if view === textView, let item = codeBlockCopyMenuItem(at: charIndex) { menu.addItem(item) }
        let items = PreviewCommand.contextMenuItems(includesGoToLine: view === textView && selectedMode != .rendered) { [weak self] command in
            guard let self else { return }
            // A chosen item is a deliberate request, so Copy All skips the key handler's focus rule.
            if command == .copyConcealed {
                self.copyAllSafeText()
            } else if let shortcut = PreviewShortcut(command: command) {
                _ = self.handleShortcut(shortcut)
            }
        }
        for item in items { menu.addItem(item) }
        return menu
    }
}

/// What was copied, so a view can tell the preview without saying how it was shown.
struct PreviewCopyEvent: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Text the reader selected or the whole displayed text.
        case text
        /// The whole concealed document, from Copy Concealed Text.
        case concealedSource
        /// Table or outline rows.
        case rows(Int)
        /// A key path.
        case path
    }

    let kind: Kind
    let removedTagScalarCount: Int

    init(kind: Kind, removedTagScalarCount: Int = 0) {
        self.kind = kind
        self.removedTagScalarCount = removedTagScalarCount
    }

    static let text = Self(kind: .text)
    static let concealedSource = Self(kind: .concealedSource)
    static let path = Self(kind: .path)
    static func rows(_ count: Int) -> Self { .init(kind: .rows(count)) }
    func removingTags(_ count: Int) -> Self { .init(kind: kind, removedTagScalarCount: count) }
    var confirmationKey: PreviewStrings.Key { removedTagScalarCount > 0 ? .chipCopiedTagsRemoved : .chipCopied }
}

/// Copy destinations and the current presentation's policy are injected by the hosting preview.
@MainActor
protocol PreviewSafeCopying: AnyObject {
    var pasteboard: NSPasteboard { get set }
    var tagCopyPolicy: (() -> Bool)? { get set }
}

extension PreviewSafeCopying {
    func sanitizedCopyText(_ text: String) -> TagSanitizedCopy {
        TagCopySanitizer(safeDisplayedText: text, safetyLensFoundTags: tagCopyPolicy?() ?? false).wholeText()
    }
}

/// A view that copies on its own reports each copy here, once, after the pasteboard write. The preview shows the
/// chip and makes the announcement; a view never speaks or draws a confirmation itself.
@MainActor
protocol PreviewCopyReporting: AnyObject {
    var copyHandler: ((PreviewCopyEvent) -> Void)? { get set }
}

/// A view that says something on its own (a sort result, a filter count) shares the preview's announcer instead of
/// posting an accessibility notification itself, so one policy and one test handler cover everything the preview
/// says. The preview sets `announcer` when it hosts the view; a view used alone may keep an announcer of its own.
@MainActor
protocol PreviewAnnouncing: AnyObject {
    var announcer: PreviewAnnouncer? { get set }
}

/// The preview's text view: it reports a copy of a selection (Command-C and the Copy menu item) through
/// `PreviewCopyReporting`.
@MainActor
final class PreviewTextView: NSTextView, PreviewCopyReporting, PreviewSafeCopying {
    var copyHandler: ((PreviewCopyEvent) -> Void)?
    var pasteboard = NSPasteboard.general
    var tagCopyPolicy: (() -> Bool)?
    /// Uses AppKit's selection writer for every representation and reports its real result.
    var selectionWriter: (NSTextView, NSPasteboard, [NSPasteboard.PasteboardType]) -> Bool = {
        // A selected payload made entirely of unsafe Tags deliberately replaces the clipboard with empty text.
        $0.selectedRanges.allSatisfy { $0.rangeValue.length == 0 }
            ? $1.setString("", forType: .string) : $0.writeSelection(to: $1, types: $2)
    }
    /// App-authored inert styling survives a gated copy. Links, attachments, alternatives and opaque document
    /// attributes can serialize content that is absent from the string, so that copy snapshot omits them.
    private static let copyStylingKeys: Set<NSAttributedString.Key> = [
        .font, .foregroundColor, .backgroundColor, .paragraphStyle, .ligature, .kern, .baselineOffset,
        .underlineStyle, .underlineColor, .strikethroughStyle, .strikethroughColor, .strokeWidth, .strokeColor,
        .obliqueness, .expansion, .writingDirection, .superscript, .shadow
    ]
    /// The top of the stack `makeTextKit1()` builds. A text view made around a stack of its own does not keep the
    /// text storage alive, so this does.
    private var textKit1Storage: NSTextStorage?

    /// A text view on a TextKit 1 stack (the layout manager the gutter, Go to Line and the reading position use).
    /// The stack is built by hand so the class that comes back is always this one; a class factory such as
    /// `init(usingTextLayoutManager:)` makes no promise about a subclass.
    static func makeTextKit1() -> PreviewTextView {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        let container = NSTextContainer(containerSize: NSSize(width: CGFloat.greatestFiniteMagnitude,
                                                              height: CGFloat.greatestFiniteMagnitude))
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        let view = PreviewTextView(frame: .zero, textContainer: container)
        view.textKit1Storage = storage
        return view
    }

    override func copy(_ sender: Any?) {
        // Nothing selected means nothing is copied, so nothing is confirmed.
        let ranges = selectedRanges.map(\.rangeValue)
        guard ranges.contains(where: { $0.length > 0 }) else { return }
        let stripsTags = tagCopyPolicy?() ?? false
        let sanitizer = TagCopySanitizer(safeDisplayedText: string, safetyLensFoundTags: stripsTags)
        var removedCount = 0
        for range in ranges {
            guard range.location != NSNotFound, range.length <= Int.max - range.location,
                  let selection = sanitizer.selection(range.location..<(range.location + range.length)) else { return }
            removedCount += selection.removedTagScalarCount
        }
        let whole = sanitizer.wholeText()
        let copiedStorage = NSMutableAttributedString(attributedString: attributedString())
        if stripsTags {
            copiedStorage.enumerateAttributes(in: NSRange(location: 0, length: copiedStorage.length)) { attributes, range, _ in
                for key in attributes.keys where !Self.copyStylingKeys.contains(key) {
                    copiedStorage.removeAttribute(key, range: range)
                }
            }
        }
        for deletion in whole.removedUTF16Ranges.reversed() { copiedStorage.deleteCharacters(in: NSRange(deletion)) }
        let writer = NSTextView(frame: .zero)
        writer.isRichText = isRichText
        writer.textStorage?.setAttributedString(copiedStorage)
        func copiedOffset(_ offset: Int) -> Int {
            offset - whole.removedUTF16Ranges.reduce(0) { count, deletion in
                count + max(0, min(offset, deletion.upperBound) - deletion.lowerBound)
            }
        }
        writer.selectedRanges = ranges.map { range in
            NSValue(range: NSRange(location: copiedOffset(range.location),
                                  length: copiedOffset(range.location + range.length) - copiedOffset(range.location)))
        }
        pasteboard.clearContents()
        guard selectionWriter(writer, pasteboard, writablePasteboardTypes) else { return }
        copyHandler?(.text.removingTags(removedCount))
    }
}
