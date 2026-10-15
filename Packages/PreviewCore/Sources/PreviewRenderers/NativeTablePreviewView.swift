import AppKit
import PreviewContracts

/// A native table of already-concealed cells. Cells, copy output and accessibility values come only
/// from `SafeTable`. Columns are rebuilt only when the table itself changes; restyling updates the
/// fonts and colors of existing cells in place and never touches the data, selection or scroll position.
///
/// Rows can be sorted (a header click, or the Sort menu for keyboard use) and filtered (the search field,
/// Command-F). Both only reorder or hide row *indexes*: the table, its exact cell text and the copy
/// output are untouched, so neither can reveal anything the privacy filter concealed. The column header
/// stays visible while the rows scroll, and rows alternate in background color.
@MainActor
final class NativeTablePreviewView: NSView, NSTableViewDataSource, NSTableViewDelegate, PreviewAnnouncing, PreviewCopyReporting, PreviewSafeCopying {
    private static let cellIdentifier = NSUserInterfaceItemIdentifier("safe-table-cell")
    /// The concealment token the privacy filter writes; a cell holding exactly it is drawn as a comment.
    private static let concealmentToken = SecretFieldPolicy.concealmentToken
    private static let minimumColumnWidth: CGFloat = 56
    private static let maximumColumnWidth: CGFloat = 360
    /// Column widths come from the header and a bounded sample of leading rows and characters.
    private static let sizedRows = 200
    private static let sizedCharacters = 40
    private static let tooltipMinimumLength = 24
    private static let tooltipCharacters = 1_000

    let scrollView = NSScrollView()
    let tableView = SafeCopyTableView()
    /// Hides rows whose cells do not contain the typed text.
    let filterField = NSSearchField()
    /// Chooses the sort column and direction without a pointer; a pull-down menu.
    let sortButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let filterStatusLabel = NSTextField(labelWithString: "")
    private let filterBar = NSStackView()
    private let stack = NSStackView()
    private var table: SafeTable?
    /// Source row indexes in display order: the current sort, then the filter.
    private var order: [Int] = []
    /// Every source row index in the current sort, before filtering.
    private var sortedOrder: [Int] = []
    private var sort: (column: Int, ascending: Bool)?
    private var filter = SafeTableFilter()
    private var filterText = ""
    private var isSyncingSortDescriptors = false
    private var presentationLocale = Locale.current
    private var columnIndexes: [NSUserInterfaceItemIdentifier: Int] = [:]
    private var stylePass: NativeTextStylePass?
    private var glyphWidth: CGFloat = 0
    /// A table made on its own keeps this announcer; the hosting preview replaces it with its own.
    var announcer: PreviewAnnouncer? = PreviewAnnouncer()
    /// Receives each copy of rows once, after the pasteboard write; the hosting preview confirms it.
    var copyHandler: ((PreviewCopyEvent) -> Void)?
    var pasteboard: NSPasteboard {
        get { tableView.pasteboard }
        set { tableView.pasteboard = newValue }
    }
    var tagCopyPolicy: (() -> Bool)? {
        get { tableView.tagCopyPolicy }
        set { tableView.tagCopyPolicy = newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = tableView
        tableView.dataSource = self
        tableView.delegate = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnReordering = false
        tableView.allowsColumnSelection = false
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.intercellSpacing = NSSize(width: 12, height: 0)
        tableView.safeCopy = { [weak self] in self?.selectedSafeText() ?? "" }
        tableView.didCopyRows = { [weak self] event in self?.reportCopy(event) }
        tableView.focusFilter = { [weak self] in _ = self?.showFilter() }
        configureFilterBar()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(filterBar)
        stack.addArrangedSubview(scrollView)
        // The filter keeps its natural height; the table takes the remaining space.
        filterBar.setContentHuggingPriority(.required, for: .vertical)
        filterBar.setContentCompressionResistancePriority(.required, for: .vertical)
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func display(_ table: SafeTable, typography requested: PreviewTypography, palette: NativeTextPalette,
                 syntaxStyle: PreviewSyntaxStyle, locale: Locale) {
        let typography = NativeTextTypography(requested, syntaxStyle: syntaxStyle)
        let previousGlyphWidth = glyphWidth
        glyphWidth = Self.glyphWidth(of: typography.font)
        stylePass = NativeTextStylePass(typography: typography, palette: palette, syntaxStyle: syntaxStyle)
        layer?.backgroundColor = palette.background.cgColor
        tableView.backgroundColor = palette.background
        scrollView.backgroundColor = palette.background
        // The result count is secondary chrome text: the palette's muted ink, not a system secondary ink that ignores
        // the color scheme.
        filterStatusLabel.textColor = palette.muted
        let rowHeight = max(24, typography.font.pointSize + CGFloat(requested.lineSpacing) + 8)
        if tableView.rowHeight != rowHeight { tableView.rowHeight = rowHeight }
        let changed = self.table != table
        let localeChanged = presentationLocale != locale
        presentationLocale = locale
        if changed {
            self.table = table
            resetOrdering(for: table)
            rebuildColumns(for: table, font: typography.font)
            configureFilterControls(for: table)
            tableView.reloadData()
            tableView.deselectAll(nil)
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else {
            if localeChanged { configureFilterControls(for: table) }
            rescaleColumns(by: previousGlyphWidth > 0 ? glyphWidth / previousGlyphWidth : 1)
            // Include prefetched/in-flight row views, not only the current visible rect.
            let columns = tableView.tableColumns
            tableView.enumerateAvailableRowViews { rowView, row in
                for columnIndex in 0..<min(rowView.numberOfColumns, columns.count) {
                    guard let field = rowView.view(atColumn: columnIndex) as? NSTextField,
                          let column = self.columnIndexes[columns[columnIndex].identifier] else { continue }
                    self.configure(field, row: row, column: column)
                }
            }
        }
        filterBar.isHidden = false
        updateAccessibilityLabel()
    }

    /// Releases the data and returns the view to a neutral state for the next preview.
    func clear() {
        table = nil
        columnIndexes = [:]
        order = []
        sortedOrder = []
        sort = nil
        filterText = ""
        filterField.stringValue = ""
        filter.reset()
        filterStatusLabel.stringValue = ""
        filterStatusLabel.isHidden = true
        filterBar.isHidden = true
        removeAllColumns()
        tableView.reloadData()
        tableView.deselectAll(nil)
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        tableView.setAccessibilityLabel(nil)
    }

    // MARK: Data source and delegate

    func numberOfRows(in tableView: NSTableView) -> Int { order.count }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard !isSyncingSortDescriptors, let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key, let column = Int(key) else { return }
        applySort(column: column, ascending: descriptor.ascending)
        announceSort(column: column, ascending: descriptor.ascending)
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, let column = columnIndexes[tableColumn.identifier] else { return nil }
        let field = tableView.makeView(withIdentifier: Self.cellIdentifier, owner: self) as? NSTextField
            ?? SafeTableCellField(labelWithString: "")
        if field.identifier != Self.cellIdentifier { prepare(field) }
        configure(field, row: row, column: column)
        return field
    }

    // MARK: Cells

    /// One-time properties. Reused cells keep them, so per-cell work stays small for wide tables.
    private func prepare(_ field: NSTextField) {
        field.identifier = Self.cellIdentifier
        field.isSelectable = true
        field.isEditable = false
        field.lineBreakMode = .byTruncatingTail
        (field.cell as? NSTextFieldCell)?.usesSingleLineMode = true
    }

    private func configure(_ field: NSTextField, row: Int, column: Int) {
        guard let table, let stylePass, order.indices.contains(row) else { return }
        let text = table.cell(row: order[row], column: column)
        let attributes = text == Self.concealmentToken ? stylePass.attributes(for: .comment) : stylePass.baseAttributes
        // One row stays one line: the cell shows line breaks and tabs as spaces; the tooltip keeps them.
        field.attributedStringValue = NSAttributedString(string: Self.singleLine(text), attributes: attributes)
        let tooltip = text.utf8.count > Self.tooltipMinimumLength ? String(text.prefix(Self.tooltipCharacters)) : nil
        if field.toolTip != tooltip { field.toolTip = tooltip }
        // The column title gives each value its context for assistive technology.
        let label = table.columns.indices.contains(column) ? table.columns[column] : nil
        if field.accessibilityLabel() != label { field.setAccessibilityLabel(label) }
        // Reused cells must drop a previous spoken description, so it is assigned every time. Descriptions are
        // keyed by source row, like the text above, so a sorted or filtered table reads each cell's own.
        (field as? SafeTableCellField)?.spokenValue = table.description(row: order[row], column: column)
    }

    // MARK: Columns

    private func rebuildColumns(for table: SafeTable, font: NSFont) {
        removeAllColumns()
        var indexes: [NSUserInterfaceItemIdentifier: Int] = [:]
        indexes.reserveCapacity(table.columns.count)
        for (index, title) in table.columns.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("safe-table-column-\(index)"))
            column.title = title
            column.headerToolTip = title
            column.minWidth = Self.minimumColumnWidth
            column.maxWidth = 4_000
            column.resizingMask = .userResizingMask
            column.headerCell.lineBreakMode = .byTruncatingTail
            // Clicking the header sorts by this column; `sortDescriptorsDidChange` does the work.
            column.sortDescriptorPrototype = NSSortDescriptor(key: String(index), ascending: true)
            column.width = preferredWidth(of: index, in: table)
            indexes[column.identifier] = index
            tableView.addTableColumn(column)
        }
        columnIndexes = indexes
    }

    /// Keeps user-resized widths proportional when only the font metrics change.
    private func rescaleColumns(by widthScale: CGFloat) {
        guard widthScale != 1 else { return }
        for column in tableView.tableColumns {
            column.width = min(max(column.width * widthScale, column.minWidth), column.maxWidth)
        }
    }

    private func removeAllColumns() {
        isSyncingSortDescriptors = true
        tableView.sortDescriptors = []
        isSyncingSortDescriptors = false
        for column in tableView.tableColumns { tableView.removeTableColumn(column) }
    }

    private func preferredWidth(of index: Int, in table: SafeTable) -> CGFloat {
        var longest = min(table.columns[index].utf16.count, Self.sizedCharacters)
        for row in table.rows.prefix(Self.sizedRows) where index < row.count {
            longest = max(longest, min(row[index].utf16.count, Self.sizedCharacters))
        }
        return min(max(CGFloat(longest) * glyphWidth + 28, Self.minimumColumnWidth), Self.maximumColumnWidth)
    }

    private static func glyphWidth(of font: NSFont) -> CGFloat {
        max(1, ("0" as NSString).size(withAttributes: [.font: font]).width)
    }

    // MARK: Sorting and filtering

    private func configureFilterBar() {
        filterField.sendsSearchStringImmediately = true
        filterField.sendsWholeSearchString = false
        filterField.target = self
        filterField.action = #selector(filterFieldChanged(_:))
        filterField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        filterField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        // Its ink is the palette's muted tier, set with every `display`.
        filterStatusLabel.font = .preferredFont(forTextStyle: .caption1)
        filterStatusLabel.lineBreakMode = .byTruncatingTail
        filterStatusLabel.setContentHuggingPriority(.required, for: .horizontal)
        filterStatusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        filterStatusLabel.isHidden = true
        sortButton.setContentHuggingPriority(.required, for: .horizontal)
        filterBar.orientation = .horizontal
        filterBar.alignment = .centerY
        filterBar.distribution = .fill
        filterBar.spacing = 8
        filterBar.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        filterBar.translatesAutoresizingMaskIntoConstraints = false
        for view in [filterField, filterStatusLabel, sortButton] as [NSView] { filterBar.addArrangedSubview(view) }
        filterBar.isHidden = true
    }

    /// Localized labels of the filter field and the Sort menu. Rebuilt when the table or locale changes.
    private func configureFilterControls(for table: SafeTable) {
        filterField.placeholderString = PreviewStrings.text(.listingFilterPlaceholder)
        filterField.setAccessibilityLabel(PreviewStrings.text(.listingFilterLabel))
        filterField.setAccessibilityHelp(PreviewStrings.text(.listingFilterHelp))
        let menu = NSMenu()
        menu.autoenablesItems = false
        // A pull-down button shows its first item as its title.
        menu.addItem(withTitle: PreviewStrings.text(.listingSortMenu), action: nil, keyEquivalent: "")
        for (index, title) in table.columns.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(chooseSortColumn(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (title, ascending) in [(PreviewStrings.text(.listingSortAscending), true), (PreviewStrings.text(.listingSortDescending), false)] {
            let item = NSMenuItem(title: title, action: #selector(chooseSortDirection(_:)), keyEquivalent: "")
            item.target = self
            item.tag = ascending ? 1 : 0
            menu.addItem(item)
        }
        sortButton.menu = menu
        sortButton.setAccessibilityLabel(PreviewStrings.text(.listingSortMenu))
        updateSortMenuState()
        updateFilterStatus()
    }

    private func updateSortMenuState() {
        guard let menu = sortButton.menu else { return }
        for item in menu.items {
            switch item.action {
            case #selector(chooseSortColumn(_:))?: item.state = sort?.column == item.tag ? .on : .off
            case #selector(chooseSortDirection(_:))?:
                item.isEnabled = sort != nil
                item.state = sort.map { $0.ascending == (item.tag == 1) } == true ? .on : .off
            default: break
            }
        }
    }

    /// The original row order, no filter, no sort indicator: what a freshly displayed table shows.
    private func resetOrdering(for table: SafeTable) {
        sort = nil
        filterText = ""
        filterField.stringValue = ""
        filter.reset()
        sortedOrder = Array(table.rows.indices)
        order = sortedOrder
    }

    @objc private func chooseSortColumn(_ item: NSMenuItem) {
        setSortDescriptor(column: item.tag, ascending: sort?.ascending ?? true)
    }

    @objc private func chooseSortDirection(_ item: NSMenuItem) {
        guard let sort else { return }
        setSortDescriptor(column: sort.column, ascending: item.tag == 1)
    }

    /// Sorts from the Sort menu. Setting the table's descriptors keeps the header's sort indicator in
    /// step; the delegate callback is suppressed because the sort is applied here directly.
    func sortRows(column: Int, ascending: Bool) {
        guard let table, table.columns.indices.contains(column) else { return }
        isSyncingSortDescriptors = true
        tableView.sortDescriptors = [NSSortDescriptor(key: String(column), ascending: ascending)]
        isSyncingSortDescriptors = false
        applySort(column: column, ascending: ascending)
        announceSort(column: column, ascending: ascending)
    }

    private func setSortDescriptor(column: Int, ascending: Bool) {
        sortRows(column: column, ascending: ascending)
    }

    @objc private func filterFieldChanged(_ field: NSSearchField) {
        setFilter(field.stringValue)
        announceFilterResult()
    }

    /// Shows the filter bar if it is hidden and moves keyboard focus into the filter field. The table's own Command-F
    /// and the preview's Command-F in every table mode both come here, so "from anywhere" is the same action as
    /// "with the table focused". False when no table is loaded, so the key is not taken.
    @discardableResult
    func showFilter() -> Bool {
        guard table != nil else { return false }
        filterBar.isHidden = false
        window?.makeFirstResponder(filterField)
        return true
    }

    /// Hides every row without the text; an empty text shows every row again.
    func setFilter(_ text: String) {
        if filterField.stringValue != text { filterField.stringValue = text }
        filterText = text
        applyOrder(resort: false)
    }

    /// Re-sorts all rows by `column`, then re-applies the filter.
    private func applySort(column: Int, ascending: Bool) {
        sort = (column, ascending)
        applyOrder(resort: true)
    }

    /// Recomputes the displayed rows while keeping the selected *source* rows selected if still shown.
    private func applyOrder(resort: Bool) {
        guard let table else { return }
        let selected = Set(tableView.selectedRowIndexes.compactMap { order.indices.contains($0) ? order[$0] : nil })
        if resort {
            sortedOrder = sort.map { SafeTableOrdering.sorted(table, by: $0.column, ascending: $0.ascending) }
                ?? Array(table.rows.indices)
        }
        order = filter.rows(in: sortedOrder, of: table, matching: filterText)
        tableView.reloadData()
        tableView.selectRowIndexes(IndexSet(order.indices.filter { selected.contains(order[$0]) }), byExtendingSelection: false)
        updateSortMenuState()
        updateFilterStatus()
        updateAccessibilityLabel()
    }

    private func updateFilterStatus() {
        guard let table, !filterText.isEmpty else {
            filterStatusLabel.stringValue = ""
            filterStatusLabel.isHidden = true
            return
        }
        filterStatusLabel.stringValue = filterStatusText(for: table)
        filterStatusLabel.isHidden = false
    }

    /// "n of m rows": how many rows the typed filter leaves.
    private func filterStatusText(for table: SafeTable) -> String {
        PreviewStrings.format(
            .listingFilterStatus, arguments: [Int64(order.count), Int64(table.rows.count)], locale: presentationLocale)
    }

    /// Says the result of a typed filter, zero included, as the user types. Medium priority, so it queues behind
    /// the characters being echoed. Clearing the filter is silent (every row is back), and so is a sort or a
    /// change made in code, which never come through here.
    private func announceFilterResult() {
        guard let table, !filterText.isEmpty else { return }
        announcer?.announce(filterStatusText(for: table), from: tableView, priority: .medium)
    }

    private func updateAccessibilityLabel() {
        guard let table else { return }
        tableView.setAccessibilityLabel(PreviewStrings.format(
            .previewTableAccessibilityLabel, arguments: [Int64(order.count), Int64(table.columns.count)], locale: presentationLocale))
    }

    private func announceSort(column: Int, ascending: Bool) {
        guard let table, table.columns.indices.contains(column) else { return }
        let direction = PreviewStrings.text(ascending ? .listingSortAscending : .listingSortDescending)
        let message = PreviewStrings.format(.listingSortAnnouncement, arguments: [table.columns[column], direction],
                                            locale: presentationLocale)
        announcer?.announce(message, from: tableView)
    }

    // MARK: Copy

    /// Tells the hosting preview about a copy, which confirms it once. A view with no host says so itself, so a
    /// copy is never silent.
    private func reportCopy(_ event: PreviewCopyEvent) {
        if let copyHandler {
            copyHandler(event)
        } else {
            announcer?.announce(PreviewStrings.text(event.confirmationKey), from: tableView)
        }
    }

    /// Selected rows as tab-separated lines of safe cell text. Tabs and line breaks inside a cell
    /// become spaces so every selected row stays exactly one line.
    private func selectedSafeText() -> String {
        guard let table else { return "" }
        return tableView.selectedRowIndexes.compactMap { order.indices.contains($0) ? order[$0] : nil }.map { row in
            (0..<table.columns.count).map { Self.singleLine(table.cell(row: row, column: $0)) }.joined(separator: "\t")
        }.joined(separator: "\n")
    }

    private static let lineSeparators: Set<Unicode.Scalar> = ["\t", "\n", "\r", "\u{85}", "\u{2028}", "\u{2029}"]

    private static func singleLine(_ text: String) -> String {
        // Tab, LF and CR are single bytes; NEL, LS and PS start with 0xC2 or 0xE2. Most cells have none.
        guard text.utf8.contains(where: { $0 == 0x09 || $0 == 0x0A || $0 == 0x0D || $0 == 0xC2 || $0 == 0xE2 }),
              text.unicodeScalars.contains(where: lineSeparators.contains) else { return text }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.map { lineSeparators.contains($0) ? " " : $0 })
        return String(scalars)
    }
}

/// A table cell that can be read aloud differently from how it is drawn, for example a sparkline of
/// block characters. Only cells with a description from `SafeTable` differ; every other cell reports
/// its text exactly as a plain text field does.
@MainActor
final class SafeTableCellField: NSTextField {
    var spokenValue: String?
    // The accessibility value comes from the field's cell; answering here takes precedence for assistive technology.
    @objc(accessibilityValue) func spokenAccessibilityValue() -> Any? { spokenValue ?? cell?.accessibilityValue() ?? stringValue }
}

/// Command-C copies only the safe text of the selected rows, never an unfiltered representation.
@MainActor
final class SafeCopyTableView: NSTableView, PreviewSafeCopying {
    var safeCopy: (() -> String)?
    /// Moves keyboard focus to the filter field; Command-F while the table has focus.
    var focusFilter: (() -> Void)?
    /// Tests substitute a private pasteboard so they never touch the user's clipboard.
    var pasteboard = NSPasteboard.general
    var tagCopyPolicy: (() -> Bool)?
    /// Returns whether the write succeeded; tests can exercise failure without changing the host's board.
    var selectionWriter: (String, NSPasteboard) -> Bool = { text, board in
        board.clearContents()
        return board.setString(text, forType: .string)
    }
    /// Told how many rows a copy wrote, once, after the pasteboard write.
    var didCopyRows: ((PreviewCopyEvent) -> Void)?
    @objc func copy(_ sender: Any?) {
        let text = safeCopy?() ?? ""
        guard !text.isEmpty else { return }
        let copied = sanitizedCopyText(text)
        guard selectionWriter(copied.text, pasteboard) else { return }
        didCopyRows?(.rows(selectedRowIndexes.count).removingTags(copied.removedTagScalarCount))
    }
    /// Command-C copies and Command-F moves to the filter, whatever the keyboard layout types for those keys.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, let command = PreviewCommand(event: event) {
            if command == .copy { copy(nil); return true }
            if command == .find, let focusFilter { focusFilter(); return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}
