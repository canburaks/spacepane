import AppKit
import PreviewContracts

/// What the filter currently shows, for the count label and the VoiceOver announcement.
struct OutlineFilterSummary: Equatable {
    var isActive = false
    /// Rows whose key or value contains the filter text (their ancestors are listed too but not counted).
    var matchCount = 0
}

/// A copy command for one outline row. The text always comes from the concealed node, never from source.
enum OutlineRowAction: CaseIterable {
    case value, key, path

    var title: PreviewStrings.Key {
        switch self {
        case .value: .interactionCopyValue
        case .key: .interactionCopyKey
        case .path: .interactionCopyPath
        }
    }
}

/// A native outline whose labels, values, accessibility and copy path contain only safe nodes.
@MainActor
final class NativeOutlinePreviewView: NSScrollView, NSOutlineViewDataSource, NSOutlineViewDelegate,
                                      PreviewAnnouncing, PreviewCopyReporting, PreviewSafeCopying {
    private enum Column: String { case key, value }
    private static let concealmentToken = SecretFieldPolicy.concealmentToken
    private static let regularKeyColumnWidth: CGFloat = 220
    /// A row's place in the unfiltered tree: each ancestor's name plus which same-named sibling it is.
    /// Identifies rows across a replacement of the displayed nodes (live reload) without relying on object identity.
    private struct ItemKey: Hashable {
        struct Step: Hashable { let name: String; let ordinal: Int }
        let steps: [Step]
    }
    private struct DisplayState {
        var expanded: Set<ItemKey> = []
        var selected: Set<ItemKey> = []
        var isEmpty: Bool { expanded.isEmpty && selected.isEmpty }
    }
    private let outline = SafeCopyOutlineView()
    private var roots: [OutlineItem] = []
    private var shownRoots: [OutlineItem] = []
    private var values: [SafeOutlineNode] = []
    private var stylePass: NativeTextStylePass?
    private var duplicateKeyHelp: String?
    private var rootsAreDocuments = false
    private var presentationLocale = Locale.current
    private var density: PreviewChrome.Density = .regular
    private(set) var filterQuery: OutlineFilterQuery?
    private(set) var filterSummary = OutlineFilterSummary()
    /// The state to return to when the filter is cleared; captured when filtering starts.
    private var unfilteredState: DisplayState?
    /// Called whenever the filter result is recomputed, including after the nodes are replaced.
    var onFilterResult: ((OutlineFilterSummary) -> Void)?
    /// Called with the selected row's path when a single row is selected, or `nil` otherwise.
    var onSelectionChange: ((String?) -> Void)?
    /// Tests substitute a private pasteboard so they never touch the user's clipboard.
    var pasteboard = NSPasteboard.general { didSet { outline.pasteboard = pasteboard } }
    var tagCopyPolicy: (() -> Bool)? { didSet { outline.tagCopyPolicy = tagCopyPolicy } }
    /// An outline made on its own keeps this announcer; the hosting preview replaces it with its own.
    var announcer: PreviewAnnouncer? = PreviewAnnouncer()
    /// Receives each copy of rows or of a path once, after the pasteboard write; the hosting preview confirms it.
    var copyHandler: ((PreviewCopyEvent) -> Void)?

    var selectedPath: String? {
        guard outline.selectedRowIndexes.count == 1,
              let item = outline.item(atRow: outline.selectedRow) as? OutlineItem else { return nil }
        return path(of: item)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hasVerticalScroller = true; hasHorizontalScroller = true; autohidesScrollers = true
        outline.dataSource = self; outline.delegate = self
        outline.usesAlternatingRowBackgroundColors = true
        outline.allowsMultipleSelection = true
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (kind, width) in [(Column.key, Self.regularKeyColumnWidth), (.value, CGFloat(380))] {
            let column = NSTableColumn(identifier: .init(kind.rawValue))
            column.width = width; column.minWidth = 80
            outline.addTableColumn(column)
            if kind == .key { outline.outlineTableColumn = column }
        }
        outline.target = self
        outline.doubleAction = #selector(doubleClickRow(_:))
        outline.safeCopy = { [weak self] in self?.selectedSafeText() ?? "" }
        outline.didCopyRows = { [weak self] event in self?.reportCopy(event) }
        outline.contextMenuProvider = { [weak self] rows in self?.rowMenu(for: rows) }
        documentView = outline
        needsLayout = true
    }
    required init?(coder: NSCoder) { nil }

    @objc private func doubleClickRow(_ sender: Any?) {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        toggleExpansion(atRow: row)
    }

    @discardableResult
    func toggleExpansion(atRow row: Int) -> Bool {
        guard row >= 0, row < outline.numberOfRows,
              let item = outline.item(atRow: row) as? OutlineItem,
              !item.shown.isEmpty else { return false }
        if outline.isItemExpanded(item) {
            outline.collapseItem(item)
        } else {
            outline.expandItem(item)
        }
        return true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        updateColumnWidthsForWidth(bounds.width)
        super.layout()
    }

    private func updateColumnWidthsForWidth(_ width: CGFloat) {
        let next = PreviewChrome.density(forWidth: width, previous: density)
        if let column = outline.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(Column.key.rawValue)) {
            if next == .compact || (width > 0 && width < PreviewChrome.compactWidth - PreviewChrome.compactHysteresis) {
                let target = max(column.minWidth, min(140, floor(width * 0.42)))
                if density != .compact || column.width > target {
                    column.width = target
                }
            } else if density == .compact, column.width < Self.regularKeyColumnWidth {
                column.width = Self.regularKeyColumnWidth
            }
        }
        let previousDensity = density
        density = next
        if previousDensity != next {
            outline.enumerateAvailableRowViews { rowView, row in
                guard row >= 0, row < self.outline.numberOfRows,
                      let item = self.outline.item(atRow: row) as? OutlineItem else { return }
                for columnIndex in 0..<min(rowView.numberOfColumns, self.outline.numberOfColumns) {
                    guard let field = rowView.view(atColumn: columnIndex) as? NSTextField,
                          let col = Column(rawValue: self.outline.tableColumns[columnIndex].identifier.rawValue) else { continue }
                    self.configure(field, item: item, column: col)
                }
            }
        }
    }

    /// `rootsAreDocuments` marks outlines whose top-level rows are separate documents (JSON Lines records),
    /// which only affects the paths Copy Path produces.
    func display(_ nodes: [SafeOutlineNode], typography requested: PreviewTypography,
                 palette: NativeTextPalette, syntaxStyle: PreviewSyntaxStyle, locale: Locale,
                 rootsAreDocuments: Bool = false) {
        let typography = NativeTextTypography(requested, syntaxStyle: syntaxStyle)
        stylePass = .init(typography: typography, palette: palette, syntaxStyle: syntaxStyle)
        duplicateKeyHelp = PreviewStrings.text(.previewDuplicateKey)
        self.rootsAreDocuments = rootsAreDocuments
        presentationLocale = locale
        outline.tableColumns.first?.title = PreviewStrings.text(.previewOutlineKey)
        outline.tableColumns.last?.title = PreviewStrings.text(.previewOutlineValue)
        outline.setAccessibilityLabel(PreviewStrings.text(.previewModeOutline))
        outline.backgroundColor = palette.background; backgroundColor = palette.background
        outline.rowHeight = max(24, typography.font.pointSize + CGFloat(requested.lineSpacing) + 8)
        if values != nodes {
            // A replacement of the same document (live reload) keeps what the user opened and selected
            // where those rows still exist; a first display starts with the top level expanded.
            let hadContent = !values.isEmpty
            let previous = hadContent ? captureState() : DisplayState()
            values = nodes; roots = nodes.map(OutlineItem.init)
            applyFilterState()
            outline.reloadData()
            if filterQuery != nil {
                expandFilterAncestors(in: shownRoots)
            } else if restore(previous) == 0 {
                outline.beginUpdates()
                for item in roots { outline.expandItem(item) }
                outline.endUpdates()
            }
            onFilterResult?(filterSummary)
            onSelectionChange?(selectedPath)
        } else {
            // Include prefetched/in-flight row views, not only the current visible rect.
            // Future cells use the new pass when requested by the delegate.
            outline.enumerateAvailableRowViews { rowView, row in
                guard row >= 0, row < self.outline.numberOfRows,
                      let item = self.outline.item(atRow: row) as? OutlineItem else { return }
                for columnIndex in 0..<min(rowView.numberOfColumns, self.outline.numberOfColumns) {
                    guard let field = rowView.view(atColumn: columnIndex) as? NSTextField,
                          let column = Column(rawValue: self.outline.tableColumns[columnIndex].identifier.rawValue) else { continue }
                    self.configure(field, item: item, column: column)
                }
            }
        }
    }

    func clear() {
        values = []; roots = []; shownRoots = []; unfilteredState = nil
        filterQuery = nil; filterSummary = OutlineFilterSummary()
        outline.reloadData()
        onFilterResult?(filterSummary)
        onSelectionChange?(nil)
    }

    // MARK: Data source and delegate

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? OutlineItem)?.shown.count ?? shownRoots.count
    }
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        ((item as? OutlineItem)?.shown ?? shownRoots)[index]
    }
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { !(item as! OutlineItem).shown.isEmpty }
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? OutlineItem, let identifier = tableColumn?.identifier,
              let column = Column(rawValue: identifier.rawValue) else { return nil }
        let field = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
            ?? NSTextField(labelWithString: "")
        field.identifier = identifier
        configure(field, item: item, column: column)
        return field
    }
    func outlineViewSelectionDidChange(_ notification: Notification) {
        onSelectionChange?(selectedPath)
    }
    static func displayedValueText(for node: SafeOutlineNode, locale: Locale = .current) -> String {
        guard !node.children.isEmpty, node.value == "{…}" || node.value == "[…]" else {
            return node.value
        }
        return "\(node.value) (\(node.children.count.formatted(.number.locale(locale))))"
    }

    static func valueRole(for node: SafeOutlineNode) -> PreviewSyntaxRole {
        if node.isIssue || node.value == concealmentToken || !node.children.isEmpty {
            return .comment
        }
        if node.value == "true" || node.value == "false" || node.value == "null" || node.value == "nil" {
            return .keyword
        }
        if isScalarNumber(node.value) {
            return .number
        }
        return .string
    }

    private static func isScalarNumber(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        var index = 0
        if index < bytes.count, bytes[index] == UInt8(ascii: "-") {
            index += 1
        }
        guard index < bytes.count else { return false }
        if bytes[index] == UInt8(ascii: "0") {
            index += 1
            if index < bytes.count, bytes[index] != UInt8(ascii: ".") {
                return false
            }
        } else if (UInt8(ascii: "1")...UInt8(ascii: "9")).contains(bytes[index]) {
            index += 1
            while index < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) {
                index += 1
            }
        } else {
            return false
        }
        if index == bytes.count { return true }
        guard bytes[index] == UInt8(ascii: ".") else { return false }
        index += 1
        guard index < bytes.count else { return false }
        while index < bytes.count {
            guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[index]) else { return false }
            index += 1
        }
        return true
    }

    static func shouldShowHoverTooltip(for text: String, isKey: Bool, density: PreviewChrome.Density) -> Bool {
        let count = text.utf8.count
        if isKey {
            return count > 48 || (density == .compact && count > 18)
        }
        return count > 48
    }

    private func configure(_ field: NSTextField, item: OutlineItem, column: Column) {
        guard let stylePass else { return }
        field.isSelectable = true
        field.isEditable = false
        let isKey = column == .key
        let text = isKey ? item.node.name : Self.displayedValueText(for: item.node, locale: presentationLocale)
        let role: PreviewSyntaxRole = item.node.isIssue ? .comment : isKey ? .key : Self.valueRole(for: item.node)
        field.attributedStringValue = NSAttributedString(string: text, attributes: stylePass.attributes(for: role))
        field.lineBreakMode = .byTruncatingTail
        let duplicateNote = item.node.isDuplicateKey ? (duplicateKeyHelp ?? PreviewStrings.text(.previewDuplicateKey)) : nil
        if let duplicateNote {
            field.toolTip = duplicateNote
        } else if Self.shouldShowHoverTooltip(for: text, isKey: isKey, density: density) {
            field.toolTip = String(text.prefix(1_000))
        } else {
            field.toolTip = nil
        }
        field.setAccessibilityHelp(duplicateNote)
        // The context menu is invisible to keyboard and VoiceOver users, so the same commands are actions here.
        field.setAccessibilityCustomActions(OutlineRowAction.allCases.map { action in
            NSAccessibilityCustomAction(name: PreviewStrings.text(action.title)) { [weak self, weak item] in
                guard let self, let item else { return false }
                return self.copy(action, items: [item])
            }
        })
    }

    private func selectedSafeText() -> String {
        outline.selectedRowIndexes.compactMap { row -> String? in
            guard let item = outline.item(atRow: row) as? OutlineItem else { return nil }
            return item.node.name + "\t" + item.node.value
        }.joined(separator: "\n")
    }

    // MARK: Filter

    /// Filters rows to those whose key or value contains `text`, ignoring case and diacritics. Ancestors of
    /// a match stay listed and expanded. Whitespace-only text clears the filter.
    @discardableResult
    func setFilter(_ text: String) -> OutlineFilterSummary {
        let query = OutlineFilterQuery(text)
        guard query != filterQuery else { return filterSummary }
        let selected = captureSelection()
        let startsFiltering = filterQuery == nil && query != nil
        if startsFiltering { unfilteredState = captureState() }
        let returning = query == nil ? unfilteredState : nil
        filterQuery = query
        if query == nil { unfilteredState = nil }
        applyFilterState()
        // Rows keep their expanded state across a reload, so start from all collapsed and open what applies.
        outline.collapseItem(nil, collapseChildren: true)
        outline.reloadData()
        if query != nil {
            expandFilterAncestors(in: shownRoots)
        } else if let returning, restore(returning) > 0 {
            // The pre-filter expansion is back.
        } else {
            outline.beginUpdates()
            for item in roots { outline.expandItem(item) }
            outline.endUpdates()
        }
        reselect(selected)
        onFilterResult?(filterSummary)
        onSelectionChange?(selectedPath)
        return filterSummary
    }

    /// Selects the next (or previous) matching row after the current selection, wrapping around.
    @discardableResult
    func selectAdjacentMatch(forward: Bool) -> Bool {
        guard filterQuery != nil, filterSummary.matchCount > 0, outline.numberOfRows > 0 else { return false }
        let rows = outline.numberOfRows
        let anchor = forward ? (outline.selectedRowIndexes.last ?? -1) : (outline.selectedRowIndexes.first ?? rows)
        for offset in 1...rows {
            let row = ((forward ? anchor + offset : anchor - offset) % rows + rows) % rows
            if let item = outline.item(atRow: row) as? OutlineItem, item.isMatch {
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                outline.scrollRowToVisible(row)
                return true
            }
        }
        return false
    }

    /// Recomputes which items each level lists for the current query; callers reload the view afterwards.
    private func applyFilterState() {
        guard let query = filterQuery else {
            for item in roots { item.resetFilter() }
            shownRoots = roots
            filterSummary = OutlineFilterSummary(isActive: false, matchCount: 0)
            return
        }
        var count = 0
        var kept: [OutlineItem] = []
        for item in roots {
            let result = item.applyFilter(query)
            count += result.matches
            if result.containsMatch { kept.append(item) }
        }
        shownRoots = kept
        filterSummary = OutlineFilterSummary(isActive: true, matchCount: count)
    }

    private func expandFilterAncestors(in items: [OutlineItem]) {
        for item in items where item.expandsForFilter {
            outline.expandItem(item)
            expandFilterAncestors(in: item.shown)
        }
    }

    // MARK: State across replacement

    /// Keys for every row of the unfiltered tree, so state survives a reload of changed content.
    private func keyedItems() -> [ObjectIdentifier: ItemKey] {
        var keys: [ObjectIdentifier: ItemKey] = [:]
        func visit(_ items: [OutlineItem], prefix: [ItemKey.Step]) {
            var seen: [String: Int] = [:]
            for item in items {
                let ordinal = seen[item.node.name, default: 0]
                seen[item.node.name] = ordinal + 1
                let steps = prefix + [.init(name: item.node.name, ordinal: ordinal)]
                keys[ObjectIdentifier(item)] = ItemKey(steps: steps)
                visit(item.children, prefix: steps)
            }
        }
        visit(roots, prefix: [])
        return keys
    }

    private func captureSelection() -> Set<ObjectIdentifier> {
        Set(outline.selectedRowIndexes.compactMap { (outline.item(atRow: $0) as? OutlineItem).map(ObjectIdentifier.init) })
    }

    private func reselect(_ identifiers: Set<ObjectIdentifier>) {
        guard !identifiers.isEmpty else { return }
        var rows = IndexSet()
        for row in 0..<outline.numberOfRows {
            if let item = outline.item(atRow: row) as? OutlineItem, identifiers.contains(ObjectIdentifier(item)) { rows.insert(row) }
        }
        if !rows.isEmpty { outline.selectRowIndexes(rows, byExtendingSelection: false) }
    }

    private func captureState() -> DisplayState {
        guard !roots.isEmpty else { return DisplayState() }
        let keys = keyedItems()
        var state = DisplayState()
        func visit(_ items: [OutlineItem]) {
            for item in items {
                guard outline.isItemExpanded(item) else { continue }
                if let key = keys[ObjectIdentifier(item)] { state.expanded.insert(key) }
                visit(item.shown)
            }
        }
        visit(shownRoots)
        for row in outline.selectedRowIndexes {
            if let item = outline.item(atRow: row) as? OutlineItem, let key = keys[ObjectIdentifier(item)] {
                state.selected.insert(key)
            }
        }
        return state
    }

    /// Re-expands and re-selects rows by key. Returns how many rows were expanded.
    @discardableResult
    private func restore(_ state: DisplayState) -> Int {
        guard !state.isEmpty else { return 0 }
        let keys = keyedItems()
        var expanded = 0
        func visit(_ items: [OutlineItem]) {
            for item in items {
                if let key = keys[ObjectIdentifier(item)], state.expanded.contains(key) {
                    outline.expandItem(item); expanded += 1
                    visit(item.shown)
                }
            }
        }
        visit(shownRoots)
        var rows = IndexSet()
        for row in 0..<outline.numberOfRows {
            if let item = outline.item(atRow: row) as? OutlineItem, let key = keys[ObjectIdentifier(item)],
               state.selected.contains(key) { rows.insert(row) }
        }
        if !rows.isEmpty { outline.selectRowIndexes(rows, byExtendingSelection: false) }
        return expanded
    }

    // MARK: Row copy actions

    func rowMenu(for rows: IndexSet) -> NSMenu? {
        let items = rows.compactMap { outline.item(atRow: $0) as? OutlineItem }
        guard !items.isEmpty else { return nil }
        let menu = NSMenu()
        for action in OutlineRowAction.allCases {
            let entry = NSMenuItem(title: PreviewStrings.text(action.title), action: #selector(performRowAction(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = RowActionBox(action: action, rows: rows)
            menu.addItem(entry)
        }
        return menu
    }

    private final class RowActionBox: NSObject {
        let action: OutlineRowAction
        let rows: IndexSet
        init(action: OutlineRowAction, rows: IndexSet) { self.action = action; self.rows = rows }
    }

    @objc private func performRowAction(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? RowActionBox else { return }
        perform(box.action, rows: box.rows)
    }

    /// Copies for the given rows (one line per row). Returns whether anything was written.
    @discardableResult
    func perform(_ action: OutlineRowAction, rows: IndexSet) -> Bool {
        copy(action, items: rows.compactMap { outline.item(atRow: $0) as? OutlineItem })
    }

    private func copy(_ action: OutlineRowAction, items: [OutlineItem]) -> Bool {
        guard !items.isEmpty else { return false }
        // Named `joined`: a local called `text` would shadow `text(for:item:)` inside its own initializer.
        let joined = items.map { text(for: action, item: $0) }.joined(separator: "\n")
        let copied = sanitizedCopyText(joined)
        pasteboard.clearContents()
        guard pasteboard.setString(copied.text, forType: .string) else { return false }
        reportCopy((action == .path ? PreviewCopyEvent.path : .rows(items.count)).removingTags(copied.removedTagScalarCount))
        return true
    }

    /// Tells the hosting preview about a copy, which confirms it once. A view with no host says so itself, so a
    /// copy is never silent.
    private func reportCopy(_ event: PreviewCopyEvent) {
        if let copyHandler {
            copyHandler(event)
        } else {
            announcer?.announce(PreviewStrings.text(event.confirmationKey), from: outline)
        }
    }

    /// The concealed text a copy action produces for one row.
    func text(for action: OutlineRowAction, item: OutlineItem) -> String {
        switch action {
        case .key: return item.node.name
        case .value: return item.children.isEmpty ? item.node.value : Self.subtreeText(item.node)
        case .path: return path(of: item)
        }
    }

    func path(of item: OutlineItem) -> String {
        var chain: [OutlineItem] = [item]
        var parent = outline.parent(forItem: item) as? OutlineItem
        while let current = parent {
            chain.append(current)
            parent = outline.parent(forItem: current) as? OutlineItem
        }
        var steps: [OutlinePath.Step] = []
        for (index, row) in chain.reversed().enumerated() {
            let parentValue = index > 0 ? chain.reversed()[index - 1].node.value : nil
            steps.append(.init(name: row.node.name, parentValue: parentValue))
        }
        return OutlinePath.make(steps: steps, rootsAreDocuments: rootsAreDocuments)
    }

    /// A container's value is the readable text of everything below it: one indented `key: value` line per
    /// row. The container placeholder (`{…}`) is not content, so rows with children print only their key.
    private static func subtreeText(_ node: SafeOutlineNode) -> String {
        var lines: [String] = []
        func visit(_ node: SafeOutlineNode, depth: Int) {
            let indent = String(repeating: "  ", count: depth)
            if node.children.isEmpty {
                lines.append(indent + node.name + (node.value.isEmpty ? "" : ": " + node.value))
            } else {
                lines.append(indent + node.name + ":")
                for child in node.children { visit(child, depth: depth + 1) }
            }
        }
        for child in node.children { visit(child, depth: 0) }
        return lines.joined(separator: "\n")
    }
}

@MainActor
private final class SafeCopyOutlineView: NSOutlineView, PreviewSafeCopying {
    var safeCopy: (() -> String)?
    /// Tests substitute a private pasteboard so they never touch the user's clipboard.
    var pasteboard = NSPasteboard.general
    var tagCopyPolicy: (() -> Bool)?
    /// Builds the context menu for the rows a click applies to.
    var contextMenuProvider: ((IndexSet) -> NSMenu?)?
    /// Told how many rows a copy wrote, once, after the pasteboard write.
    var didCopyRows: ((PreviewCopyEvent) -> Void)?

    @objc func copy(_ sender: Any?) {
        let text = safeCopy?() ?? ""
        guard !text.isEmpty else { return }
        let copied = sanitizedCopyText(text)
        pasteboard.clearContents()
        guard pasteboard.setString(copied.text, forType: .string) else { return }
        didCopyRows?(.rows(selectedRowIndexes.count).removingTags(copied.removedTagScalarCount))
    }
    /// Command-C copies the selected rows, whatever the keyboard layout types for the C key.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, PreviewCommand(event: event) == .copy {
            copy(nil); return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Command-Up and Command-Down (the system's document-start and document-end commands) select the first
    /// and last listed row, as in other native lists.
    override func moveToBeginningOfDocument(_ sender: Any?) { selectBoundaryRow(first: true) }
    override func moveToEndOfDocument(_ sender: Any?) { selectBoundaryRow(first: false) }

    private func selectBoundaryRow(first: Bool) {
        guard numberOfRows > 0 else { return }
        let row = first ? 0 : numberOfRows - 1
        selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        scrollRowToVisible(row)
    }

    /// A secondary click acts on the row under the pointer, or on the whole selection when that row is in it.
    override func menu(for event: NSEvent) -> NSMenu? {
        let row = row(at: convert(event.locationInWindow, from: nil))
        guard row >= 0 else { return nil }
        if !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        return contextMenuProvider?(selectedRowIndexes)
    }
}
