import AppKit
import PreviewContracts

/// The Contents mode: the headings collected while rendering, indented by level. Choosing a
/// row (click, double-click, or Return/Enter on the selected row) reveals the heading in
/// the Rendered text. Arrow keys only move the selection while the list has keyboard focus, so
/// keyboard users can browse it without leaving it. Space is never bound: Quick Look owns it
/// (`PreviewKeyPolicy`). Rows, copy output and accessibility values come only from headings that
/// were derived from already-concealed text. A wide pane embeds this same list in `MarkupContentsRail`, which
/// sets the section it follows through `showCurrent(row:)`.
@MainActor
final class MarkupContentsView: NSView, SafeModeContentView, PreviewAnnouncing, PreviewCopyReporting, PreviewSafeCopying,
                                NSTableViewDataSource, NSTableViewDelegate {
    private static let cellIdentifier = NSUserInterfaceItemIdentifier("markup-contents-cell")
    private static let columnIdentifier = NSUserInterfaceItemIdentifier("markup-contents-column")
    private static let defaultIndentPerLevel: CGFloat = 16

    var navigate: ((NativePreviewMode, NSRange) -> Void)?
    /// The leading inset added per heading level. The rail, which has a fraction of the width, sets a smaller one.
    var indentPerLevel: CGFloat = MarkupContentsView.defaultIndentPerLevel
    /// The largest size the rows are set in; nil, the default, follows the reader's typography exactly.
    var maximumPointSize: CGFloat?
    /// Whether a new document starts with its first heading selected. The rail leaves the selection to its
    /// section tracking instead, so that no row is selected before the reader's position is known.
    var selectsFirstRow = true

    let scrollView = NSScrollView()
    let tableView = ContentsTableView()
    /// Tests substitute a private pasteboard so they never touch the user's clipboard.
    var pasteboard: NSPasteboard {
        get { tableView.pasteboard }
        set { tableView.pasteboard = newValue }
    }
    var tagCopyPolicy: (() -> Bool)? {
        get { tableView.tagCopyPolicy }
        set { tableView.tagCopyPolicy = newValue }
    }
    /// The hosting preview replaces it with its own announcer.
    var announcer: PreviewAnnouncer? {
        get { tableView.announcer }
        set { tableView.announcer = newValue }
    }
    /// Receives each copy of headings once, after the pasteboard write; the hosting preview confirms it.
    var copyHandler: ((PreviewCopyEvent) -> Void)? {
        get { tableView.copyHandler }
        set { tableView.copyHandler = newValue }
    }
    private(set) var headings: [MarkupHeading] = []
    private var typography: NativeTextTypography?
    private var palette: NativeTextPalette?
    private var syntaxStyle = PreviewSyntaxStyle()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let column = NSTableColumn(identifier: Self.columnIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.doubleAction = #selector(rowClicked)
        tableView.onActivate = { [weak self] row in self?.activate(row: row) }
        tableView.safeCopy = { [weak self] in self?.selectedTitles() ?? "" }
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        tableView.setAccessibilityLabel(PreviewStrings.text(.previewModeContents))
    }

    required init?(coder: NSCoder) { nil }

    // MARK: SafeModeContentView

    /// The list of headings takes keyboard focus, not the container around it.
    var keyboardFocusTarget: NSView? { tableView }

    func display(_ modes: SafePreviewModes, mode: NativePreviewMode, style: SafeModeStyle) {
        display(headings: modes.markdown?.headings ?? [], style: style)
    }

    /// Shows `updated`, the headings the renderer collected. The Contents mode and the rail both come through here.
    func display(headings updated: [MarkupHeading], style: SafeModeStyle) {
        let resolved = NativeTextTypography(style.typography, syntaxStyle: style.syntaxStyle)
        typography = resolved
        palette = style.palette
        syntaxStyle = style.syntaxStyle
        layer?.backgroundColor = style.palette.background.cgColor
        tableView.backgroundColor = style.palette.background
        scrollView.backgroundColor = style.palette.background
        let rowPointSize = min(resolved.font.pointSize, maximumPointSize ?? resolved.font.pointSize)
        tableView.rowHeight = max(24, rowPointSize + CGFloat(style.typography.lineSpacing) + 10)
        tableView.setAccessibilityLabel(PreviewStrings.text(.previewModeContents))
        if updated != headings {
            headings = updated
            tableView.reloadData()
            tableView.deselectAll(nil)
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else {
            // Restyle existing rows in place; the selection and scroll position stay.
            tableView.enumerateAvailableRowViews { rowView, row in
                guard row >= 0, row < self.headings.count, let cell = rowView.view(atColumn: 0) as? ContentsCell else { return }
                self.configure(cell, row: row)
            }
        }
        if selectsFirstRow, tableView.selectedRow < 0, !headings.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
    }

    func clear() {
        headings = []
        tableView.reloadData()
        tableView.deselectAll(nil)
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { headings.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? ContentsCell ?? ContentsCell()
        cell.identifier = Self.cellIdentifier
        configure(cell, row: row)
        return cell
    }

    private func configure(_ cell: ContentsCell, row: Int) {
        guard headings.indices.contains(row), let typography, let palette else { return }
        let heading = headings[row]
        let role: PreviewSyntaxRole = heading.level == 1 ? .heading : .key
        var font = typography.font
        if let cap = maximumPointSize, font.pointSize > cap,
           let capped = NSFont(descriptor: font.fontDescriptor, size: cap) { font = capped }
        if heading.level == 1 { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        cell.field.attributedStringValue = NSAttributedString(string: heading.title, attributes: [
            .font: font, .foregroundColor: palette.color(for: role, style: syntaxStyle)
        ])
        cell.setIndent(10 + CGFloat(max(heading.level - 1, 0)) * indentPerLevel)
        cell.field.setAccessibilityLabel(PreviewStrings.format(.markupContentsItem,
            arguments: [Int64(heading.level), heading.title], locale: .current))
        cell.field.setAccessibilityHelp(PreviewStrings.text(.markupContentsHelp))
    }

    // MARK: Actions

    @objc private func rowClicked() {
        let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
        activate(row: row)
    }

    func activate(row: Int) {
        guard headings.indices.contains(row) else { return }
        navigate?(.rendered, headings[row].range)
    }

    /// Whether the list itself holds keyboard focus. Arrow keys move its selection only then.
    var hasKeyboardFocus: Bool { window?.firstResponder === tableView }

    /// Marks row `row` as the current section, or none for nil, without navigating, announcing or moving focus:
    /// it only selects the row and scrolls it into the list. Choosing the row that is already selected does
    /// nothing, so following a scroll never moves the list under a reader who scrolled it by hand.
    func showCurrent(row: Int?) {
        guard let row, headings.indices.contains(row) else {
            if tableView.selectedRow >= 0 { tableView.deselectAll(nil) }
            return
        }
        guard tableView.selectedRow != row else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    private func selectedTitles() -> String {
        tableView.selectedRowIndexes.compactMap { headings.indices.contains($0) ? headings[$0].title : nil }.joined(separator: "\n")
    }
}

/// A single-line row whose leading inset follows the heading level.
@MainActor
final class ContentsCell: NSTableCellView {
    let field = NSTextField(labelWithString: "")
    private var leading: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.lineBreakMode = .byTruncatingTail
        field.isSelectable = false
        addSubview(field)
        textField = field
        let inset = field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10)
        leading = inset
        NSLayoutConstraint.activate([
            inset,
            field.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            field.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func setIndent(_ value: CGFloat) { leading?.constant = value }
}

/// Return and Enter activate the selected row; copy writes the selected titles. Space and Escape are never
/// handled here: they are handed on to Quick Look (`PreviewKeyPolicy`).
@MainActor
final class ContentsTableView: NSTableView, PreviewSafeCopying {
    var onActivate: ((Int) -> Void)?
    var safeCopy: (() -> String)?
    /// Tests substitute a private pasteboard so they never touch the user's clipboard.
    var pasteboard = NSPasteboard.general
    var tagCopyPolicy: (() -> Bool)?
    /// Speaks "Find is not available here" when Find is pressed while this list has focus. A list made on its own
    /// keeps this one; the hosting preview replaces it with its own.
    var announcer: PreviewAnnouncer? = PreviewAnnouncer()
    /// Receives each copy once, after the pasteboard write. The hosting preview confirms it; a list with no
    /// host says so itself, so a copy is never silent.
    var copyHandler: ((PreviewCopyEvent) -> Void)?

    override func keyDown(with event: NSEvent) {
        if PreviewKeyPolicy.reservesForHost(keyCode: event.keyCode), let next = nextResponder {
            next.keyDown(with: event)
            return
        }
        // Return and keypad Enter show the heading; everything else keeps its default.
        if [PreviewKeyCode.returnKey, PreviewKeyCode.keypadEnter].contains(event.keyCode), selectedRow >= 0 {
            onActivate?(selectedRow)
            return
        }
        super.keyDown(with: event)
    }

    @objc func copy(_ sender: Any?) {
        let text = safeCopy?() ?? ""
        guard !text.isEmpty else { return }
        let copied = sanitizedCopyText(text)
        pasteboard.clearContents()
        guard pasteboard.setString(copied.text, forType: .string) else { return }
        let event = PreviewCopyEvent.rows(selectedRowIndexes.count).removingTags(copied.removedTagScalarCount)
        if let copyHandler {
            copyHandler(event)
        } else {
            announcer?.announce(PreviewStrings.text(event.confirmationKey), from: self)
        }
    }

    /// Command-C copies, whatever the keyboard layout types for the C key; Find has nothing to search here.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        if PreviewCommand(event: event) == .copy {
            copy(nil)
            return true
        }
        if PreviewKeyPolicy.answerFindUnavailable(event, using: announcer, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }
}
