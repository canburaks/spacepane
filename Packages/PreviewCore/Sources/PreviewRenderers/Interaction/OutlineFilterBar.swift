import AppKit

/// The search field above outline presentations and its result count. It only reports what was typed; the
/// outline performs the filtering and the preview announces the result.
@MainActor
final class OutlineFilterBar: NSView, NSSearchFieldDelegate {
    let searchField = NSSearchField()
    let countLabel = NSTextField(labelWithString: "")
    let pathLabel = NSTextField(labelWithString: "")
    private var searchMinWidthConstraint: NSLayoutConstraint?
    private var searchMaxWidthConstraint: NSLayoutConstraint?
    private var currentPath = ""
    private var isCompact = false

    /// Every change of the text, including clearing it.
    var onChange: ((String) -> Void)?
    /// Return (forward) or Shift-Return (backward) while filtering: move to the next match.
    var onAdvance: ((Bool) -> Void)?
    /// Escape pressed in an empty field: give focus back to the rows.
    var onReturnToContent: (() -> Void)?
    /// Copy Path chosen from the path label's context menu.
    var onCopyPath: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
        setAccessibilityRole(.group)
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.target = self
        searchField.action = #selector(searchChanged)
        // The count is secondary chrome text; its ink is the palette's muted tier, set in `apply(palette:)`.
        countLabel.font = .preferredFont(forTextStyle: .caption1)
        countLabel.lineBreakMode = .byTruncatingTail
        countLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        pathLabel.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.isSelectable = true
        pathLabel.isHidden = true
        pathLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pathLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in [searchField, countLabel, pathLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        let minWidth = searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 140)
        let maxWidth = searchField.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        searchMinWidthConstraint = minWidth
        searchMaxWidthConstraint = maxWidth
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            minWidth,
            maxWidth,
            countLabel.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            pathLabel.leadingAnchor.constraint(greaterThanOrEqualTo: countLabel.trailingAnchor, constant: 8),
            pathLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            pathLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        localize()
    }

    required init?(coder: NSCoder) { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        updateChromeForWidth(bounds.width)
        super.layout()
    }

    private func updateChromeForWidth(_ width: CGFloat) {
        guard width > 0 else { return }
        isCompact = width < PreviewChrome.compactWidth - PreviewChrome.compactHysteresis
        searchField.controlSize = isCompact ? .small : .regular
        searchMinWidthConstraint?.constant = isCompact ? 96 : 140
        searchMaxWidthConstraint?.constant = isCompact ? 132 : 280
        updatePathVisibility()
    }

    /// Localized result text for a summary: the match count, "no matches", or nothing when not filtering.
    static func countText(for summary: OutlineFilterSummary) -> String {
        guard summary.isActive else { return "" }
        return summary.matchCount > 0
            ? PreviewStrings.format(.interactionFilterMatches, arguments: [Int64(summary.matchCount)])
            : PreviewStrings.text(.interactionFilterNoMatches)
    }

    var text: String {
        get { searchField.stringValue }
        set { searchField.stringValue = newValue }
    }

    func apply(palette: NativeTextPalette) {
        countLabel.textColor = palette.muted
        pathLabel.textColor = palette.muted
    }

    func show(_ summary: OutlineFilterSummary) {
        localize()
        let count = Self.countText(for: summary)
        countLabel.stringValue = count
        countLabel.toolTip = count.isEmpty ? nil : count
        countLabel.setAccessibilityLabel(count.isEmpty ? nil : count)
    }

    func showPath(_ path: String?) {
        currentPath = path ?? ""
        pathLabel.stringValue = currentPath
        pathLabel.toolTip = currentPath.isEmpty ? nil : currentPath
        updatePathVisibility()
    }

    private func updatePathVisibility() {
        pathLabel.isHidden = currentPath.isEmpty || isCompact
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard !pathLabel.isHidden, pathLabel.frame.contains(point) else { return super.menu(for: event) }
        return pathContextMenu()
    }

    func pathContextMenu() -> NSMenu? {
        guard !currentPath.isEmpty else { return nil }
        let menu = NSMenu(title: "")
        menu.autoenablesItems = false
        let item = NSMenuItem(title: PreviewStrings.text(.interactionCopyPath), action: #selector(copyCurrentPath(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func copyCurrentPath(_ sender: Any?) {
        onCopyPath?()
    }

    func focus() {
        window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    private func localize() {
        searchField.placeholderString = PreviewStrings.text(.interactionFilterPlaceholder)
        searchField.setAccessibilityLabel(PreviewStrings.text(.interactionFilterLabel))
        searchField.setAccessibilityHelp(PreviewStrings.text(.interactionFilterHelp))
        setAccessibilityLabel(PreviewStrings.text(.interactionFilterLabel))
    }

    /// Sent for every keystroke (the field sends its string immediately) and when its clear button is used.
    @objc private func searchChanged() { onChange?(searchField.stringValue) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            if searchField.stringValue.isEmpty { onReturnToContent?() }
            else { searchField.stringValue = ""; onChange?("") }
            return true
        case #selector(NSResponder.insertNewline(_:)):
            // Shift reverses direction; the class property reflects the keys held right now.
            onAdvance?(!NSEvent.modifierFlags.contains(.shift))
            return true
        default:
            return false
        }
    }
}
