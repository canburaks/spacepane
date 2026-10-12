import AppKit

/// The search field above outline presentations and its result count. It only reports what was typed; the
/// outline performs the filtering and the preview announces the result.
@MainActor
final class OutlineFilterBar: NSView, NSSearchFieldDelegate {
    let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")

    /// Every change of the text, including clearing it.
    var onChange: ((String) -> Void)?
    /// Return (forward) or Shift-Return (backward) while filtering: move to the next match.
    var onAdvance: ((Bool) -> Void)?
    /// Escape pressed in an empty field: give focus back to the rows.
    var onReturnToContent: (() -> Void)?

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
        for view in [searchField, countLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),
            searchField.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            countLabel.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 8),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        localize()
    }

    required init?(coder: NSCoder) { nil }

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
    }

    func show(_ summary: OutlineFilterSummary) {
        localize()
        let count = Self.countText(for: summary)
        countLabel.stringValue = count
        countLabel.setAccessibilityLabel(count.isEmpty ? nil : count)
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
