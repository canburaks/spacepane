import AppKit
import PreviewContracts

/// The Tree mode of every listing: paths nested into folders, with each folder's item count and
/// listed size. Names, counts, sizes, dates, copy output and accessibility values all come from the
/// already-concealed listing; nothing here reads a file or a preference.
@MainActor
final class NativeListingTreeView: NSView, SafeModeContentView, PreviewCopyReporting, PreviewAnnouncing, PreviewSafeCopying,
                                   NSOutlineViewDataSource, NSOutlineViewDelegate {
    /// SF Symbol names are string-only API, so they live in one place.
    private enum Symbol: String {
        case folder = "folder", file = "doc", symlink = "link", package = "shippingbox"
    }

    private enum Column: String, CaseIterable {
        case name, items, size, modified
    }

    private final class Item: NSObject {
        let node: SafeListingTree.Node
        let children: [Item]
        init(_ node: SafeListingTree.Node) {
            self.node = node
            children = node.children.map(Item.init)
            super.init()
        }
    }

    /// Trees up to this many nodes open fully expanded; larger ones open collapsed to the top level.
    static let autoExpandLimit = 300

    let scrollView = NSScrollView()
    let outlineView = SafeCopyOutlineTreeView()
    var navigate: ((NativePreviewMode, NSRange) -> Void)?
    /// The preview shows its "Copied" chip and speaks once for each copy it hears about here (`PreviewCopyReporting`).
    var copyHandler: ((PreviewCopyEvent) -> Void)?
    var pasteboard: NSPasteboard {
        get { outlineView.pasteboard }
        set { outlineView.pasteboard = newValue }
    }
    var tagCopyPolicy: (() -> Bool)? {
        get { outlineView.tagCopyPolicy }
        set { outlineView.tagCopyPolicy = newValue }
    }
    /// Speaks a copy only while no preview listens through `copyHandler`, so one copy is confirmed once, not twice.
    /// The preview hands its own announcer in (`PreviewAnnouncing`); a view used alone keeps this one.
    var announcer: PreviewAnnouncer? = PreviewAnnouncer()

    private let stack = NSStackView()
    private var tree: SafeListingTree?
    private var items: [Item] = []
    private var stylePass: NativeTextStylePass?
    /// The palette of the last display: icons are drawn in its muted ink, never a system ink that ignores the scheme.
    private var palette: NativeTextPalette?
    private var locale = Locale.current

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = outlineView
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.allowsMultipleSelection = true
        outlineView.allowsColumnReordering = false
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outlineView.autosaveExpandedItems = false
        for (kind, width) in [(Column.name, CGFloat(320)), (.items, 80), (.size, 120), (.modified, 170)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(kind.rawValue))
            column.width = width
            column.minWidth = kind == .name ? 120 : 56
            column.resizingMask = kind == .name ? [.autoresizingMask, .userResizingMask] : .userResizingMask
            outlineView.addTableColumn(column)
            if kind == .name { outlineView.outlineTableColumn = column }
        }
        outlineView.safeCopy = { [weak self] in self?.selectedSafeText() ?? "" }
        outlineView.didCopy = { [weak self] event in self?.reportCopy(event) }
        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(scrollView)
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

    // MARK: SafeModeContentView

    func display(_ modes: SafePreviewModes, mode: NativePreviewMode, style: SafeModeStyle) {
        guard mode == .tree, let tree = modes.tree else { clear(); return }
        let typography = NativeTextTypography(style.typography, syntaxStyle: style.syntaxStyle)
        let pass = NativeTextStylePass(typography: typography, palette: style.palette, syntaxStyle: style.syntaxStyle)
        let previousLocale = locale
        stylePass = pass
        palette = style.palette
        locale = style.locale
        layer?.backgroundColor = style.palette.background.cgColor
        outlineView.backgroundColor = style.palette.background
        scrollView.backgroundColor = style.palette.background
        outlineView.rowHeight = max(24, typography.font.pointSize + CGFloat(style.typography.lineSpacing) + 8)
        for column in outlineView.tableColumns {
            guard let kind = Column(rawValue: column.identifier.rawValue) else { continue }
            column.title = Self.title(of: kind, usesUTC: tree.usesUTC)
        }
        outlineView.setAccessibilityLabel(PreviewStrings.text(.listingTreeAccessibilityLabel))
        if self.tree != tree {
            self.tree = tree
            items = tree.roots.map(Item.init)
            outlineView.reloadData()
            outlineView.deselectAll(nil)
            if tree.nodeCount <= Self.autoExpandLimit { outlineView.expandItem(nil, expandChildren: true) }
            scrollView.contentView.scroll(to: .zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        } else {
            refreshAvailableRows(localeChanged: previousLocale != style.locale)
        }
    }

    func clear() {
        tree = nil
        items = []
        outlineView.reloadData()
        outlineView.deselectAll(nil)
        outlineView.setAccessibilityLabel(nil)
    }

    // MARK: Data source and delegate

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Item)?.children.count ?? items.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        ((item as? Item)?.children ?? items)[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? Item)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? Item, let identifier = tableColumn?.identifier,
              let column = Column(rawValue: identifier.rawValue) else { return nil }
        if column == .name {
            let cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? makeNameCell(identifier)
            configureName(cell, item: item)
            return cell
        }
        let field = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTextField ?? makeValueField(identifier)
        configureValue(field, item: item, column: column)
        return field
    }

    // MARK: Cells

    private func makeNameCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let image = NSImageView()
        image.translatesAutoresizingMaskIntoConstraints = false
        image.imageScaling = .scaleProportionallyDown
        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.lineBreakMode = .byTruncatingMiddle
        text.isSelectable = true
        cell.addSubview(image)
        cell.addSubview(text)
        cell.imageView = image
        cell.textField = text
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    private func makeValueField(_ identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
        let field = NSTextField(labelWithString: "")
        field.identifier = identifier
        field.isSelectable = true
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    private func configureName(_ cell: NSTableCellView, item: Item) {
        guard let stylePass else { return }
        let node = item.node
        cell.textField?.attributedStringValue = NSAttributedString(string: node.name, attributes: stylePass.baseAttributes)
        cell.textField?.toolTip = node.path == node.name ? nil : node.path
        let kind = SafeListingFormatting.kindLabel(node.kind)
        cell.imageView?.image = NSImage(systemSymbolName: Self.symbol(for: node).rawValue, accessibilityDescription: kind)
        cell.imageView?.contentTintColor = palette?.muted
        cell.textField?.setAccessibilityLabel(PreviewStrings.text(.summaryName))
        cell.textField?.setAccessibilityHelp(kind)
    }

    private func configureValue(_ field: NSTextField, item: Item, column: Column) {
        guard let stylePass else { return }
        let text = valueText(item.node, column: column)
        field.attributedStringValue = NSAttributedString(string: text, attributes: stylePass.baseAttributes)
        field.setAccessibilityLabel(Self.title(of: column, usesUTC: tree?.usesUTC ?? false))
    }

    private func valueText(_ node: SafeListingTree.Node, column: Column) -> String {
        switch column {
        case .name: return node.name
        case .items:
            guard node.isFolder, let count = node.itemCount else { return "" }
            let text = SafeListingFormatting.countText(count, locale: locale)
            return node.itemCountIsLowerBound ? SafeListingFormatting.atLeast(text, locale: locale) : text
        case .size:
            let bytes = node.isFolder ? node.listedBytes : node.bytes
            guard let bytes else { return "" }
            let text = SafeListingFormatting.sizeText(bytes, locale: locale)
            return node.isFolder && node.listedBytesIsLowerBound ? SafeListingFormatting.atLeast(text, locale: locale) : text
        case .modified:
            return node.modified.map { SafeListingFormatting.dateText($0, locale: locale, usesUTC: tree?.usesUTC ?? false) } ?? ""
        }
    }

    private func refreshAvailableRows(localeChanged: Bool) {
        // Include prefetched row views; future cells are configured with the current pass on demand.
        outlineView.enumerateAvailableRowViews { rowView, row in
            guard let item = self.outlineView.item(atRow: row) as? Item else { return }
            for index in 0..<min(rowView.numberOfColumns, self.outlineView.tableColumns.count) {
                guard let column = Column(rawValue: self.outlineView.tableColumns[index].identifier.rawValue) else { continue }
                if column == .name, let cell = rowView.view(atColumn: index) as? NSTableCellView {
                    self.configureName(cell, item: item)
                } else if let field = rowView.view(atColumn: index) as? NSTextField {
                    self.configureValue(field, item: item, column: column)
                }
            }
        }
    }

    private static func title(of column: Column, usesUTC: Bool) -> String {
        switch column {
        case .name: PreviewStrings.text(.summaryName)
        case .items: PreviewStrings.text(.listingItems)
        case .size: PreviewStrings.text(.listingColumnSize)
        case .modified: PreviewStrings.text(usesUTC ? .listingModifiedUTC : .listingModified)
        }
    }

    private static func symbol(for node: SafeListingTree.Node) -> Symbol {
        if node.isFolder { return .folder }
        switch node.kind {
        case "symlink": return .symlink
        case "package": return .package
        default: return .file
        }
    }

    // MARK: Copy

    /// One confirmation per copy: through the preview when it listens, otherwise spoken here.
    private func reportCopy(_ event: PreviewCopyEvent) {
        if let copyHandler {
            copyHandler(event)
        } else {
            announcer?.announce(PreviewStrings.text(event.confirmationKey), from: outlineView)
        }
    }

    /// Selected rows as tab-separated lines: path, item count, size, modified. Tabs and line breaks
    /// inside a path become spaces so each row stays one line.
    private func selectedSafeText() -> String {
        outlineView.selectedRowIndexes.compactMap { row -> String? in
            guard let item = outlineView.item(atRow: row) as? Item else { return nil }
            let node = item.node
            let cells = [node.path, valueText(node, column: .items), valueText(node, column: .size), valueText(node, column: .modified)]
            return cells.map { Self.singleLine($0) }.joined(separator: "\t")
        }.joined(separator: "\n")
    }

    private static func singleLine(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { "\t\n\r\u{85}\u{2028}\u{2029}".unicodeScalars.contains($0) ? " " : $0 }))
    }
}

/// Command-C copies only the safe text of the selected rows.
@MainActor
final class SafeCopyOutlineTreeView: NSOutlineView, PreviewSafeCopying {
    var safeCopy: (() -> String)?
    /// Called once after each copy that wrote to the pasteboard, with the number of rows copied.
    var didCopy: ((PreviewCopyEvent) -> Void)?
    /// Tests substitute a private pasteboard so they never touch the user's clipboard.
    var pasteboard = NSPasteboard.general
    var tagCopyPolicy: (() -> Bool)?

    @objc func copy(_ sender: Any?) {
        let text = safeCopy?() ?? ""
        guard !text.isEmpty else { return }
        let copied = sanitizedCopyText(text)
        pasteboard.clearContents()
        guard pasteboard.setString(copied.text, forType: .string) else { return }
        didCopy?(.rows(selectedRowIndexes.count).removingTags(copied.removedTagScalarCount))
    }

    /// Command-C copies, whatever the keyboard layout types for the C key.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if window?.firstResponder === self, PreviewCommand(event: event) == .copy {
            copy(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
