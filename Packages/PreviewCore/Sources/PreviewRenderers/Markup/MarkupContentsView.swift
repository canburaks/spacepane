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
    /// Space a title keeps clear of the row's edges: the leading inset before the level indent, and the trailing one.
    private static let baseLeadingInset: CGFloat = 10
    private static let trailingInset: CGFloat = 8
    /// What the text field's own cell leaves unused on each side of its text.
    private static let fieldTextMargin: CGFloat = 2
    /// The most lines a heading may take; the rest is truncated, so one long title cannot fill the list.
    static let maximumTitleLines = 5

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
    /// What the row heights depend on besides the titles: the clip width (a legacy scroller narrows it), the font
    /// and the base row height, and the indent. Heights are measured again only when this changes or the titles do.
    private struct MeasurementKey: Equatable {
        let clipWidth: CGFloat
        let fontName: String
        let pointSize: CGFloat
        let rowHeight: CGFloat
        let maximumPointSize: CGFloat?
        let indentPerLevel: CGFloat
    }
    private var measuredKey: MeasurementKey?
    /// One measuring object for every row; tests read its counters.
    let measurer = ContentsRowMeasurer()

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
        tableView.allSafeCopy = { [weak self] in self?.allTitles() ?? "" }
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
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(clipWidthChanged),
            name: NSView.frameDidChangeNotification, object: scrollView.contentView)
    }

    required init?(coder: NSCoder) { nil }

    @objc private func clipWidthChanged() { remeasureRowsIfMeasurementKeyChanged(reloaded: false) }

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
        let reloaded = updated != headings
        if reloaded {
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
        remeasureRowsIfMeasurementKeyChanged(reloaded: reloaded)
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

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard headings.indices.contains(row), typography != nil else { return tableView.rowHeight }
        let width = titleWidth(for: headings[row])
        guard width > 0 else { return tableView.rowHeight }
        let font = titleFont(for: headings[row])
        let lineHeight = measurer.lineHeight(for: font)
        // Whatever the single-line row keeps above and below its one line is kept around every extra line too, and
        // never less than the field's own insets, which a large font can leave no room for in the base height.
        let padding = max(tableView.rowHeight - lineHeight, 2 * ContentsCell.verticalInset)
        let wrapped = measurer.wrappedHeight(of: headings[row].title, font: font, width: width)
        let lines = min(max(wrapped, lineHeight), lineHeight * CGFloat(Self.maximumTitleLines))
        return max(tableView.rowHeight, lines + padding)
    }

    /// The width a title can use now. It comes from the column as it fits the clip view at this moment, never from a
    /// width kept from an earlier layout: the table style insets the column from the clip, and a legacy scroller
    /// that appears takes its width from the clip, so rows measured before that would be too short.
    private func titleWidth(for heading: MarkupHeading) -> CGFloat {
        guard scrollView.contentView.bounds.width > 0, let column = tableView.tableColumns.first else { return 0 }
        return column.width - leadingInset(for: heading) - Self.trailingInset - 2 * Self.fieldTextMargin
    }

    private func leadingInset(for heading: MarkupHeading) -> CGFloat {
        Self.baseLeadingInset + CGFloat(max(heading.level - 1, 0)) * indentPerLevel
    }

    private func titleFont(for heading: MarkupHeading) -> NSFont {
        var font = typography?.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        if let cap = maximumPointSize, font.pointSize > cap,
           let capped = NSFont(descriptor: font.fontDescriptor, size: cap) { font = capped }
        if heading.level == 1 { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        return font
    }

    /// Measures every row again when what the heights depend on is not what they were measured for. A reload has
    /// just measured the rows (the table asks for every height), so it only records the key.
    private func remeasureRowsIfMeasurementKeyChanged(reloaded: Bool) {
        let key = MeasurementKey(clipWidth: scrollView.contentView.bounds.width,
                                 fontName: typography?.font.fontName ?? "", pointSize: typography?.font.pointSize ?? 0,
                                 rowHeight: tableView.rowHeight, maximumPointSize: maximumPointSize,
                                 indentPerLevel: indentPerLevel)
        guard key != measuredKey else { return }
        let widthChanged = key.clipWidth != measuredKey?.clipWidth
        measuredKey = key
        // The column follows the clip; bring it level with the clip as it is now before measuring against it.
        if widthChanged { tableView.sizeLastColumnToFit() }
        guard !headings.isEmpty, !(reloaded && !widthChanged) else { return }
        // The table animates a height change; a resize or a scroller appearing should move rows at once.
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        tableView.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<headings.count))
        NSAnimationContext.endGrouping()
    }

    private func configure(_ cell: ContentsCell, row: Int) {
        guard headings.indices.contains(row), typography != nil, let palette else { return }
        let heading = headings[row]
        let role: PreviewSyntaxRole = heading.level == 1 ? .heading : .key
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        cell.field.attributedStringValue = NSAttributedString(string: heading.title, attributes: [
            .font: titleFont(for: heading), .foregroundColor: palette.color(for: role, style: syntaxStyle),
            .paragraphStyle: paragraph
        ])
        cell.field.maximumNumberOfLines = Self.maximumTitleLines
        cell.setIndent(leadingInset(for: heading))
        cell.field.toolTip = heading.title.utf8.count > 24 ? heading.title : nil
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

    private func allTitles() -> String {
        headings
            .map { String(repeating: "  ", count: max(0, $0.level - 1)) + $0.title }
            .joined(separator: "\n")
    }
}

/// Measures heading titles for the list's rows with one text system for every row: the layout manager, text
/// container and storage are made once, and the line height of a font is kept. The counters let tests see that
/// rows are measured once and that no layout manager is made per row.
@MainActor
final class ContentsRowMeasurer {
    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    private var lineHeights: [String: CGFloat] = [:]
    /// Layout managers made by this measurer: one for its whole life.
    private(set) var layoutManagerCount = 1
    /// Titles measured so far.
    private(set) var measurementCount = 0

    init() {
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
    }

    func lineHeight(for font: NSFont) -> CGFloat {
        let key = "\(font.fontName)/\(font.pointSize)"
        if let known = lineHeights[key] { return known }
        let height = layoutManager.defaultLineHeight(for: font).rounded(.up)
        lineHeights[key] = height
        return height
    }

    /// The height `title` takes wrapped to `width` points, unbounded in lines.
    func wrappedHeight(of title: String, font: NSFont, width: CGFloat) -> CGFloat {
        measurementCount += 1
        storage.setAttributedString(NSAttributedString(string: title, attributes: [.font: font]))
        container.size = NSSize(width: max(width, 1), height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        return layoutManager.usedRect(for: container).height.rounded(.up)
    }
}

/// A row whose leading inset follows the heading level and whose title wraps.
@MainActor
final class ContentsCell: NSTableCellView {
    /// Space the title field keeps above and below itself in the row.
    static let verticalInset: CGFloat = 3
    let field = NSTextField(labelWithString: "")
    private var leading: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        field.translatesAutoresizingMaskIntoConstraints = false
        // A title wraps (up to `maximumTitleLines`, then truncates), and the list makes the row as tall as the
        // wrapped title. The field fills the row between small insets instead of sizing itself from one line.
        field.lineBreakMode = .byWordWrapping
        field.cell?.truncatesLastVisibleLine = true
        field.usesSingleLineMode = false
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        field.isSelectable = false
        addSubview(field)
        textField = field
        let inset = field.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10)
        leading = inset
        NSLayoutConstraint.activate([
            inset,
            field.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            field.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalInset),
            field.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalInset)
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
    var allSafeCopy: (() -> String)?
    /// Tests substitute a private pasteboard so they never touch the user's clipboard.
    var pasteboard = NSPasteboard.general
    var tagCopyPolicy: (() -> Bool)?
    var selectionWriter: (String, NSPasteboard) -> Bool = { text, board in
        board.clearContents()
        return board.setString(text, forType: .string)
    }
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

    override func moveToBeginningOfDocument(_ sender: Any?) {
        guard numberOfRows > 0 else { return }
        selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        scrollRowToVisible(0)
    }

    override func moveToEndOfDocument(_ sender: Any?) {
        guard numberOfRows > 0 else { return }
        let last = numberOfRows - 1
        selectRowIndexes(IndexSet(integer: last), byExtendingSelection: false)
        scrollRowToVisible(last)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let clickedRow = row(at: point)
        guard clickedRow >= 0 else { return nil }
        if !selectedRowIndexes.contains(clickedRow) {
            selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
        }
        return contextMenu(forRow: clickedRow)
    }

    func contextMenu(forRow row: Int) -> NSMenu? {
        guard row >= 0, row < numberOfRows else { return nil }
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false
        let item = NSMenuItem(title: PreviewStrings.text(.interactionCopy), action: #selector(copy(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        let copyAll = NSMenuItem(title: PreviewStrings.text(.interactionCopyAll), action: #selector(copyAllHeadings(_:)), keyEquivalent: "")
        copyAll.target = self
        menu.addItem(copyAll)
        return menu
    }

    @objc func copy(_ sender: Any?) {
        let text = safeCopy?() ?? ""
        guard !text.isEmpty else { return }
        let copied = sanitizedCopyText(text)
        guard selectionWriter(copied.text, pasteboard) else { return }
        reportCopy(PreviewCopyEvent.rows(selectedRowIndexes.count).removingTags(copied.removedTagScalarCount))
    }

    @objc func copyAllHeadings(_ sender: Any?) {
        guard let text = allSafeCopy?(), !text.isEmpty else { return }
        let copied = sanitizedCopyText(text)
        guard selectionWriter(copied.text, pasteboard) else { return }
        reportCopy(.text.removingTags(copied.removedTagScalarCount))
    }

    private func reportCopy(_ event: PreviewCopyEvent) {
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
